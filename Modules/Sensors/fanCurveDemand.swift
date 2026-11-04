import Foundation

/// Pure rule evaluation. A baseline and a thermal curve can be enabled separately.
internal struct FanCurveDemand {
    var progress: Double?
    var emergency: Bool = false
}

internal struct FanCurveState {
    private var engaged = false
    private var safetyDemand = false
    private var sustainedSeconds: TimeInterval = 0

    mutating func evaluate(curveEnabled: Bool, baselineEnabled: Bool, temperature: Double?,
                           safetyTemperature: Double?, start: Int, ceiling: Int,
                           elapsed: TimeInterval) -> FanCurveDemand {
        guard curveEnabled || baselineEnabled else {
            self = Self()
            return FanCurveDemand(progress: nil)
        }
        if let safetyTemperature, safetyTemperature >= 95 {
            self.safetyDemand = true
        } else if let safetyTemperature, safetyTemperature < 90 {
            self.safetyDemand = false
        }
        if self.safetyDemand { return FanCurveDemand(progress: 1, emergency: true) }

        let validTemperature = temperature.map { $0.isFinite && $0 > 0 && $0 < 120 } ?? false
        guard !curveEnabled || validTemperature else {
            // A missing thermal input releases ownership, including the baseline.
            self = Self()
            return FanCurveDemand(progress: nil)
        }
        guard curveEnabled, let temperature else {
            self.engaged = false
            self.sustainedSeconds = 0
            return FanCurveDemand(progress: baselineEnabled ? 0 : nil)
        }
        if !self.engaged {
            self.sustainedSeconds = temperature >= Double(start)
                ? self.sustainedSeconds + min(max(elapsed, 0), 1.5) : 0
            self.engaged = self.sustainedSeconds >= 8
        }
        if temperature <= Double(start - 5) {
            self.engaged = false
            self.sustainedSeconds = 0
        }
        guard self.engaged else { return FanCurveDemand(progress: baselineEnabled ? 0 : nil) }
        return FanCurveDemand(progress: min(max((temperature - Double(start)) / Double(max(ceiling - start, 1)), 0), 1))
    }

    static func rpm(progress: Double, baselineEnabled: Bool, base: Int, maximum: Int,
                    hardwareMinimum: Int, hardwareMaximum: Int, emergency: Bool) -> Int {
        if emergency { return hardwareMaximum }
        let lower = min(max(hardwareMinimum, 1000), hardwareMaximum)
        let upper = min(max(maximum, lower), hardwareMaximum)
        let floor = baselineEnabled ? min(max(base, lower), upper) : lower
        return Int((Double(floor) + Double(upper - floor) * min(max(progress, 0), 1)).rounded())
    }
}
