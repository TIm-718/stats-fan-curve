# Stats temperature fan curve

This customized Stats build adds an optional temperature rule to the existing Sensors module. It adapts curve evaluation and safety behavior from the MIT-licensed MacFanPro project; the control bridge and service installer are bundled inside Stats. See `References/MacFanPro/LICENSE` and `Contents/Resources/ThirdPartyNotices/` for attribution.

## Rule behavior (851.3)

- Baseline hold and temperature curve have independent, persistent switches. Either one keeps the Sensors reader active at 1 second, including when only its label widget is visible.
- Per physical fan, the editable base RPM defaults to 2200 and the maximum defaults to the old percentage cap times hardware maximum. Existing curve settings are preserved. New profiles leave both switches off.
- UI accepts whole RPM within max(1000, hardware minimum)...hardware maximum and requires maximum >= base. Runtime clamps stored settings again for each fan.
- Baseline alone holds a constant RPM. Combined mode linearly interpolates base...maximum between the two selected temperatures. Curve alone interpolates hardware floor...maximum and releases to macOS below start minus 5 °C.
- The curve still requires about 8 seconds of sustained heat and ramps upward at 5% of hardware maximum per second, downward at 2.5%. Constant RPM targets are reasserted every 5 seconds.
- At 95 °C on a CPU/GPU sensor, hardware maximum overrides the custom cap; clears below 90 °C. Missing selected temperature while the curve is enabled releases ownership.
- Disabling either switch preserves the other. Direct manual popup adjustments disable both; old saved manual speeds never override an active rule during startup or wake.
- Sleep, reader pause/stop and normal termination restore Apple automatic control; preferences stay enabled for resume/relaunch.
- Command completion generations prevent old callbacks from consuming newer writes after an automatic handoff.

## Verification and local builds

- `bash scripts/test-fan-rules.sh` tests the production evaluator, including sustained triggers, hysteresis, custom low temperatures, missing input, independent switches, interpolation, hardware limits and overheat overrides.
- `bash scripts/build-kit-local.sh` rebuilds Kit using its existing Objective-C object. Disk metadata calls now use bounded timeouts so an unresponsive external disk cannot block fan control startup indefinitely.
- `bash scripts/build-sensors-local.sh` rebuilds Sensors using local Kit and the existing sensor C object. Signing and packaging follow after copying both frameworks into the app template.

## Fan service

Writing fan speed through the system management controller requires one-time administrator authorization on each Mac. Stats invokes a temporary installer bundled inside its own app, then removes that temporary setup copy. The installed privilege component is a background LaunchDaemon; it is not a second app users need to open. The command-line control tool stays bundled inside Stats.

The service is already installed on the development Mac. No separate MacFanPro GUI is required.

## Local package

The single user-facing app is `运行程序/Stats.app`, installed as `/Applications/Stats.app`. The Stats interface and fan rule are in the same app. The current package is built for Apple Silicon with the macOS Command Line Tools Swift compiler; Xcode is not needed to install or run it.
