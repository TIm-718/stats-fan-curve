//
//  fanCurve.swift
//  Sensors
//
//  Temperature-driven fan curve for the Stats Sensors module.
//  Curve shaping, sustained triggers, hysteresis, and ramp limiting are adapted
//  from MacFanPro's MIT-licensed Profile.swift and ThermalMonitor.swift.
//  See References/MacFanPro/LICENSE for the upstream license.
//

import Cocoa
import Kit

internal struct FanSpeedLimits: Codable, Equatable {
    var baseRPM: Int
    var maximumRPM: Int
}

internal struct FanCurveConfiguration: Equatable {
    static let startTemperatureRange = 0...104
    static let ceilingTemperatureRange = 1...105
    private static let enabledKey = "Sensors_fanCurveEnabled"
    private static let sensorKey = "Sensors_fanCurveSensor"
    private static let startKey = "Sensors_fanCurveStart"
    private static let ceilingKey = "Sensors_fanCurveCeiling"
    private static let speedKey = "Sensors_fanCurveSpeed"

    var baselineEnabled: Bool = false
    var fanSpeeds: [String: FanSpeedLimits] = [:]
    var isActive: Bool { self.enabled || self.baselineEnabled }

    var enabled: Bool
    var sensor: String
    var startTemperature: Int
    var ceilingTemperature: Int
    var maximumSpeedPercent: Int

    static let `default` = FanCurveConfiguration(
        enabled: false,
        sensor: "",
        startTemperature: 60,
        ceilingTemperature: 80,
        maximumSpeedPercent: 100
    )

    static func load() -> FanCurveConfiguration {
        var value = FanCurveConfiguration(
            enabled: Store.shared.bool(key: self.enabledKey, defaultValue: self.default.enabled),
            sensor: Store.shared.string(key: self.sensorKey, defaultValue: self.default.sensor),
            startTemperature: Store.shared.int(key: self.startKey, defaultValue: self.default.startTemperature),
            ceilingTemperature: Store.shared.int(key: self.ceilingKey, defaultValue: self.default.ceilingTemperature),
            maximumSpeedPercent: Store.shared.int(key: self.speedKey, defaultValue: self.default.maximumSpeedPercent)
        )
        value.baselineEnabled = Store.shared.bool(key: "Sensors_fanBaselineEnabled", defaultValue: false)
        if let data = Store.shared.string(key: "Sensors_fanSpeedLimits", defaultValue: "{}").data(using: .utf8),
           let speeds = try? JSONDecoder().decode([String: FanSpeedLimits].self, from: data) {
            value.fanSpeeds = speeds
        }
        value.normalize()
        return value
    }

    mutating func normalize() {
        self.startTemperature = min(max(self.startTemperature, Self.startTemperatureRange.lowerBound), Self.startTemperatureRange.upperBound)
        self.ceilingTemperature = min(max(self.ceilingTemperature, self.startTemperature + 1), Self.ceilingTemperatureRange.upperBound)
        self.maximumSpeedPercent = min(max(self.maximumSpeedPercent, 25), 100)
    }

    func limits(for fan: Fan) -> FanSpeedLimits {
        let lower = min(max(1000, Int(fan.minSpeed)), Int(fan.maxSpeed))
        let saved = self.fanSpeeds[String(fan.id)]
        let upper = min(max(saved?.maximumRPM ?? Int(fan.maxSpeed * Double(self.maximumSpeedPercent) / 100), lower), Int(fan.maxSpeed))
        return FanSpeedLimits(baseRPM: min(max(saved?.baseRPM ?? 2200, lower), upper), maximumRPM: upper)
    }

    func save() {
        Store.shared.set(key: "Sensors_fanBaselineEnabled", value: self.baselineEnabled)
        if let data = try? JSONEncoder().encode(self.fanSpeeds), let json = String(data: data, encoding: .utf8) {
            Store.shared.set(key: "Sensors_fanSpeedLimits", value: json)
        }
        Store.shared.set(key: Self.enabledKey, value: self.enabled)
        Store.shared.set(key: Self.sensorKey, value: self.sensor)
        Store.shared.set(key: Self.startKey, value: self.startTemperature)
        Store.shared.set(key: Self.ceilingKey, value: self.ceilingTemperature)
        Store.shared.set(key: Self.speedKey, value: self.maximumSpeedPercent)
    }
}

/// Evaluates the selected sensor at Stats' sensor polling cadence and delegates
/// fan writes to MacFanPro's installed privileged service.
internal final class FanCurveController {
    static let shared = FanCurveController()

    private let queue = DispatchQueue(label: "eu.exelban.Stats.fanCurve")
    private var configuration = FanCurveConfiguration.load()
    private var state = FanCurveState()
    private var lastSampleUptime: TimeInterval?
    private var controlledFanIDs = Set<Int>()
    private var pendingSpeedIDs: [Int: Int] = [:]
    private var lastAppliedRPM: [Int: Int] = [:]
    private var lastWriteUptime: [Int: TimeInterval] = [:]
    private var controlGeneration = 0

    private init() {}

    func updateConfiguration(_ value: FanCurveConfiguration) {
        self.queue.async {
            var normalized = value
            normalized.normalize()
            let changed = self.configuration != normalized
            self.configuration = normalized
            if changed { self.resetCurveState() }
            // Editing a curve or disabling just one feature keeps the other in control.
            if !normalized.isActive { self.restoreAutomaticControl() }
        }
    }

    func consume(_ sensors: [Sensor_p]) {
        self.queue.async {
            let fans = sensors.compactMap { $0 as? Fan }.filter { !$0.isComputed && $0.maxSpeed > 1 }
            guard self.configuration.isActive, !fans.isEmpty else {
                self.resetCurveState()
                self.restoreAutomaticControl()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = self.lastSampleUptime.map { min(max(now - $0, 0), 1.5) } ?? 1
            self.lastSampleUptime = now
            let temperature = sensors.first {
                $0.key == self.configuration.sensor && $0.type == .temperature
            }?.value
            let demand = self.state.evaluate(
                curveEnabled: self.configuration.enabled, baselineEnabled: self.configuration.baselineEnabled,
                temperature: temperature, safetyTemperature: self.safetyTemperature(in: sensors),
                start: self.configuration.startTemperature, ceiling: self.configuration.ceilingTemperature, elapsed: elapsed
            )
            guard let progress = demand.progress else {
                self.restoreAutomaticControl()
                return
            }
            guard MacFanProBridge.shared.isInstalled else { return }
            for fan in fans where fan.maxSpeed > fan.minSpeed {
                let limits = self.configuration.limits(for: fan)
                let target = FanCurveState.rpm(
                    progress: progress, baselineEnabled: self.configuration.baselineEnabled,
                    base: limits.baseRPM, maximum: limits.maximumRPM,
                    hardwareMinimum: Int(fan.minSpeed), hardwareMaximum: Int(fan.maxSpeed), emergency: demand.emergency
                )
                self.controlledFanIDs.insert(fan.id)
                self.writeSpeed(for: fan, target: target, elapsed: elapsed, bypassRamp: demand.emergency)
            }
        }
    }

    /// A direct fan control action in the popup takes ownership away from the
    /// automatic rule, preventing the two controls from fighting each other.
    func userTookControl() {
        self.queue.sync {
            guard self.configuration.isActive else { return }
            self.configuration.enabled = false
            self.configuration.baselineEnabled = false
            self.configuration.save()
            self.resetCurveState()
            self.restoreAutomaticControl()
            NotificationCenter.default.post(name: .fanCurveDisabledByManualControl, object: nil)
        }
    }

    /// Stop controlling fans when the Sensors reader pauses or the Mac sleeps.
    /// The preference remains enabled so the curve resumes after the reader wakes.
    func pauseAndRestoreAutomatic() {
        self.queue.async {
            self.resetCurveState()
            self.restoreAutomaticControl()
        }
    }

    private func safetyTemperature(in sensors: [Sensor_p]) -> Double? {
        sensors.filter {
            $0.type == .temperature && ($0.group == .CPU || $0.group == .GPU) &&
                $0.value.isFinite && $0.value > 0 && $0.value < 120
        }.map(\.value).max()
    }

    private func writeSpeed(for fan: Fan, target: Int, elapsed: TimeInterval, bypassRamp: Bool) {
        guard self.pendingSpeedIDs[fan.id] == nil else { return }
        var targetRPM = Double(target)
        let startingRPM = Double(self.lastAppliedRPM[fan.id] ?? Int(max(fan.value, fan.minSpeed)))
        if !bypassRamp {
            let rate = targetRPM >= startingRPM ? 0.05 : 0.025
            let maxChange = Double(fan.maxSpeed) * rate * max(elapsed, 0.25)
            targetRPM = startingRPM + min(max(targetRPM - startingRPM, -maxChange), maxChange)
        }
        let boundedRPM = Int(min(max(targetRPM.rounded(), fan.minSpeed), fan.maxSpeed))
        let now = ProcessInfo.processInfo.systemUptime
        // Reassert even a constant speed, so firmware resets cannot silently cancel the hold.
        if self.lastAppliedRPM[fan.id] == boundedRPM,
           now - (self.lastWriteUptime[fan.id] ?? 0) < 5 { return }
        let generation = self.controlGeneration
        self.pendingSpeedIDs[fan.id] = generation
        MacFanProBridge.shared.setSpeed(fanID: fan.id, rpm: boundedRPM) { success in
            self.queue.async {
                guard generation == self.controlGeneration,
                      self.pendingSpeedIDs[fan.id] == generation else { return }
                self.pendingSpeedIDs.removeValue(forKey: fan.id)
                if success {
                    self.lastAppliedRPM[fan.id] = boundedRPM
                    self.lastWriteUptime[fan.id] = now
                } else {
                    self.lastAppliedRPM.removeValue(forKey: fan.id)
                    NSLog("Stats fan rule could not set fan %d to %d RPM", fan.id, boundedRPM)
                }
            }
        }
    }

    private func resetCurveState() {
        self.state = FanCurveState()
        self.lastSampleUptime = nil
    }

    private func restoreAutomaticControl() {
        let ids = self.controlledFanIDs.union(self.pendingSpeedIDs.keys)
        guard !ids.isEmpty else { return }

        self.controlGeneration += 1
        self.controlledFanIDs.removeAll()
        self.pendingSpeedIDs.removeAll()
        self.lastAppliedRPM.removeAll()
        self.lastWriteUptime.removeAll()
        guard MacFanProBridge.shared.isInstalled else { return }

        MacFanProBridge.shared.restoreAutomatic { success in
            if !success {
                NSLog("Stats temperature fan curve could not restore Apple automatic fan control")
            }
        }
    }
}

internal extension Notification.Name {
    static let fanCurveDisabledByManualControl = Notification.Name("fanCurveDisabledByManualControl")
}
