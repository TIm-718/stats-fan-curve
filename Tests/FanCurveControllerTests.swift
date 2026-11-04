import Cocoa
import Kit

// A recording bridge replaces the privileged service for these integration tests.
final class MacFanProBridge {
    static let shared = MacFanProBridge()
    var isInstalled = true
    private let lock = NSLock()
    private var recorded: [(Int, Int)] = []
    private var restores = 0
    var writes: [(Int, Int)] { lock.lock(); defer { lock.unlock() }; return recorded }
    var restoreCount: Int { lock.lock(); defer { lock.unlock() }; return restores }
    func setSpeed(fanID: Int, rpm: Int, completion: @escaping (Bool) -> Void) {
        lock.lock(); recorded.append((fanID, rpm)); lock.unlock()
        DispatchQueue.main.async { completion(true) }
    }
    func restoreAutomatic(completion: @escaping (Bool) -> Void) {
        lock.lock(); restores += 1; lock.unlock()
        DispatchQueue.main.async { completion(true) }
    }
}

@main
struct FanCurveControllerTests {
    static func main() {
        // The test app has its own preferences domain; it never touches Stats settings or hardware.
        precondition(Bundle.main.bundleIdentifier == "com.linzihao.StatsFanRuleTests")
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }; checks += 1
        }
        func drain() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)) }
        let fan = Fan(id: 0, key: "F0Ac", name: "Test", minSpeed: 1000, maxSpeed: 4900, value: 2200, mode: .forced)
        var config = FanCurveConfiguration.default
        config.maximumSpeedPercent = 60
        check(config.limits(for: fan).maximumRPM == 2940, "migrate legacy percentage cap")
        config.baselineEnabled = true
        config.fanSpeeds["0"] = FanSpeedLimits(baseRPM: 2200, maximumRPM: 4000)
        config.save()
        check(FanCurveConfiguration.load() == config, "switches and per-fan RPM persist")
        config.fanSpeeds["0"] = FanSpeedLimits(baseRPM: -50, maximumRPM: 99000)
        check(config.limits(for: fan) == FanSpeedLimits(baseRPM: 1000, maximumRPM: 4900), "stored RPM clamped to hardware")
        config.fanSpeeds["0"] = FanSpeedLimits(baseRPM: 2200, maximumRPM: 4000)
        let controller = FanCurveController.shared
        controller.updateConfiguration(config); controller.consume([fan]); drain()
        check(MacFanProBridge.shared.writes.last?.1 == 2200, "restart takes over previous manual mode")
        config.enabled = true; config.sensor = "missing"
        controller.updateConfiguration(config); controller.consume([fan]); drain()
        check(MacFanProBridge.shared.restoreCount == 1, "missing curve input releases to Apple")
        config.enabled = false
        controller.updateConfiguration(config); controller.consume([fan]); drain()
        check(MacFanProBridge.shared.writes.count == 2, "disabling curve leaves baseline running")
        controller.pauseAndRestoreAutomatic(); drain()
        check(MacFanProBridge.shared.restoreCount == 2, "sleep/pause releases")
        controller.consume([fan]); drain()
        check(MacFanProBridge.shared.writes.count == 3, "wake/relaunch reclaims baseline")
        controller.userTookControl(); drain()
        let stored = FanCurveConfiguration.load()
        check(!stored.enabled && !stored.baselineEnabled, "manual popup disables both rules")
        check(MacFanProBridge.shared.restoreCount == 3, "manual handoff releases previous hold")
        let writeCount = MacFanProBridge.shared.writes.count
        controller.consume([fan]); drain()
        check(MacFanProBridge.shared.writes.count == writeCount, "no writes after both disabled")
        print("PASS: \(checks) controller/persistence checks; recording bridge only")
    }
}
