//
//  macFanProBridge.swift
//  Sensors
//
//  Fan-write adapter for the bundled MacFanPro CLI. Stats keeps its existing
//  sensor and fan UI; MacFanPro's installed background service performs SMC
//  writes and owns the corresponding safety/watchdog behavior.
//

import Cocoa
import Darwin
import Foundation

internal final class MacFanProBridge {
    static let shared = MacFanProBridge()

    private let queue = DispatchQueue(label: "eu.exelban.Stats.macFanProBridge")
    private let fileManager = FileManager.default

    private var embeddedAppURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/MacFanPro.app", isDirectory: true)
    }

    private var cliURL: URL {
        self.embeddedAppURL.appendingPathComponent("Contents/Helpers/macfanpro")
    }

    private var servicePlistPath: String {
        "/Library/LaunchDaemons/io.github.macfanpro.daemon.plist"
    }

    private init() {}

    var isInstalled: Bool {
        self.fileManager.fileExists(atPath: self.cliURL.path) &&
            self.fileManager.fileExists(atPath: self.servicePlistPath)
    }

    func installService(completion: @escaping (Bool, String?) -> Void) {
        self.queue.async {
            let stagedAppURL = URL(fileURLWithPath: "/Applications/MacFanPro.app", isDirectory: true)
            let stagedCLI = stagedAppURL.appendingPathComponent("Contents/Helpers/macfanpro")
            var copiedForSetup = false

            guard self.fileManager.isExecutableFile(atPath: self.cliURL.path),
                  self.fileManager.fileExists(atPath: self.embeddedAppURL.path) else {
                DispatchQueue.main.async { completion(false, "The bundled fan service installer is missing.") }
                return
            }

            do {
                if !self.fileManager.fileExists(atPath: stagedAppURL.path) {
                    try self.fileManager.copyItem(at: self.embeddedAppURL, to: stagedAppURL)
                    copiedForSetup = true
                }
                guard self.fileManager.isExecutableFile(atPath: stagedCLI.path) else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
            } catch {
                if copiedForSetup { self.trashSetupCopy(at: stagedAppURL) }
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }

            let command = "\(Self.shellQuote(stagedCLI.path)) install --embedded-owner-uid \(getuid())"
            let script = """
            on run argv
                try
                    do shell script (item 1 of argv) with administrator privileges
                    return "STATS_FAN_SERVICE_OK"
                on error detail number code
                    if code is -128 then return "STATS_FAN_SERVICE_CANCELLED"
                    error detail number code
                end try
            end run
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script, command]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output

            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let installed = process.terminationStatus == 0 && result == "STATS_FAN_SERVICE_OK" &&
                    self.fileManager.fileExists(atPath: self.servicePlistPath)
                if copiedForSetup { self.trashSetupCopy(at: stagedAppURL) }
                DispatchQueue.main.async {
                    if installed {
                        completion(true, nil)
                    } else if result == "STATS_FAN_SERVICE_CANCELLED" {
                        completion(false, "Administrator authorization was cancelled.")
                    } else {
                        completion(false, result.isEmpty ? "The fan service did not start." : result)
                    }
                }
            } catch {
                if copiedForSetup { self.trashSetupCopy(at: stagedAppURL) }
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }

    func setSpeed(fanID: Int, rpm: Int, completion: @escaping (Bool) -> Void = { _ in }) {
        self.run(["set", "\(rpm)", "--fan", "\(fanID)"], completion: completion)
    }

    func restoreAutomatic(completion: @escaping (Bool) -> Void = { _ in }) {
        self.run(["auto", "--stop-app"], completion: completion)
    }

    private func run(_ arguments: [String], completion: @escaping (Bool) -> Void) {
        self.queue.async {
            guard self.fileManager.isExecutableFile(atPath: self.cliURL.path) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let process = Process()
            process.executableURL = self.cliURL
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationReason == .exit && process.terminationStatus == 0
                DispatchQueue.main.async { completion(success) }
            } catch {
                NSLog("MacFanPro command failed: %@", error.localizedDescription)
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func trashSetupCopy(at url: URL) {
        do {
            var resultingURL: NSURL?
            try self.fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            NSLog("Could not move the temporary fan service app to the Trash: %@", error.localizedDescription)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
