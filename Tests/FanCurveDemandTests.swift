import Foundation

@main
struct FanCurveDemandTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
            checks += 1
        }
        func evaluate(_ state: inout FanCurveState, _ temperature: Double? = 45,
                      curve: Bool = true, baseline: Bool = true, safety: Double? = 45,
                      elapsed: Double = 1, start: Int = 55, ceiling: Int = 70) -> FanCurveDemand {
            state.evaluate(curveEnabled: curve, baselineEnabled: baseline, temperature: temperature,
                           safetyTemperature: safety, start: start, ceiling: ceiling, elapsed: elapsed)
        }
        var state = FanCurveState()
        check(evaluate(&state, curve: false, baseline: false).progress == nil, "both off release control")
        for _ in 0..<60 {
            check(evaluate(&state, nil, curve: false).progress == 0, "baseline alone remains held")
        }
        state = FanCurveState()
        for _ in 0..<7 { check(evaluate(&state, 62.5).progress == 0, "baseline during sustained trigger") }
        check(evaluate(&state, 62.5).progress == 0.5, "curve midpoint")
        check(evaluate(&state, 70).progress == 1, "curve ceiling")
        check(evaluate(&state, 53).progress == 0, "warm hysteresis returns to baseline")
        check(evaluate(&state, 49).progress == 0, "cold keeps baseline")
        check(evaluate(&state, 70).progress == 0, "cold resets trigger")
        check(evaluate(&state, curve: false).progress == 0, "disabling curve keeps baseline")
        check(evaluate(&state, baseline: false).progress == nil, "disabling baseline allows automatic")
        state = FanCurveState()
        for _ in 0..<7 { check(evaluate(&state, 70, baseline: false).progress == nil, "curve alone waits") }
        check(evaluate(&state, 70, baseline: false).progress == 1, "curve alone engages")
        check(evaluate(&state, 49, baseline: false).progress == nil, "curve alone releases on cooldown")
        check(evaluate(&state, nil).progress == nil, "missing selected sensor releases")
        check(evaluate(&state, .nan).progress == nil, "NaN releases")
        check(evaluate(&state, 0).progress == nil, "zero releases")
        check(evaluate(&state, 120).progress == nil, "invalid high reading releases")
        check(evaluate(&state, nil, safety: 95).emergency, "another hot CPU/GPU overrides missing sensor")
        check(evaluate(&state, safety: 92).emergency, "safety hysteresis")
        check(!evaluate(&state, safety: 89).emergency, "safety clears")
        check(evaluate(&state, curve: false, safety: 95).emergency, "baseline-only thermal safety")
        check(!evaluate(&state, curve: false, baseline: false, safety: 99).emergency, "off owns no fans")
        state = FanCurveState()
        for _ in 0..<5 { check(evaluate(&state, 70, elapsed: 100).progress == 0, "long gaps do not satisfy trigger") }
        check(evaluate(&state, 70, elapsed: 1).progress == 1, "trigger accumulates bounded intervals")
        state = FanCurveState()
        for _ in 0..<8 { _ = evaluate(&state, 35.5, start: 35, ceiling: 36) }
        check(evaluate(&state, 35.5, start: 35, ceiling: 36).progress == 0.5, "custom low temperatures and 1-degree gap")
        func rpm(_ progress: Double, _ base: Int = 2200, _ maximum: Int = 4000,
                 baseline: Bool = true, minimum: Int = 1000, hardwareMax: Int = 4900, emergency: Bool = false) -> Int {
            FanCurveState.rpm(progress: progress, baselineEnabled: baseline, base: base, maximum: maximum,
                              hardwareMinimum: minimum, hardwareMaximum: hardwareMax, emergency: emergency)
        }
        check(rpm(0) == 2200, "base is exact")
        check(rpm(0.5) == 3100, "interpolates base to user maximum")
        check(rpm(1) == 4000, "custom maximum is exact")
        check(rpm(1.5) == 4000, "above curve ceiling stays capped")
        check(rpm(-1) == 2200, "below curve start stays at base")
        check(rpm(0, baseline: false) == 1000, "curve without baseline uses minimum")
        check(rpm(0.5, baseline: false) == 2500, "curve without baseline interpolates hardware minimum")
        check(rpm(0, 100, 99000) == 1000, "invalid stored base is clamped")
        check(rpm(1, 100, 99000) == 4900, "invalid stored max is clamped")
        check(rpm(0, 4500, 3000) == 3000, "base cannot exceed ceiling")
        check(rpm(0, 1000, 4000, minimum: 1800) == 1800, "other Macs respect hardware minimum")
        check(rpm(0.5, 2200, 2200) == 2200, "equal limits hold constant")
        check(rpm(0, emergency: true) == 4900, "safety overrides custom cap")
        print("PASS: \(checks) fan rule checks")
    }
}
