//
//  settings.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 23/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v, NSTextFieldDelegate {
    private var updateIntervalValue: Int = 3
    private var hidState: Bool
    private var fanSpeedState: Bool = false
    private var fansSyncState: Bool = false
    private var unknownSensorsState: Bool = false
    private var fanValueState: FanValue = .percentage
    private var widgets: [widget_t] = []
    
    public var callback: (() -> Void) = {}
    public var HIDcallback: (() -> Void) = {}
    public var unknownCallback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }
    public var selectedHandler: (String) -> Void = {_ in }
    public var fanCurveChanged: ((FanCurveConfiguration) -> Void)?

    public var configuredUpdateInterval: Int { self.updateIntervalValue }
    
    private let title: String
    private var list: [Sensor_p] = []
    private var sensorsPrefs: PreferencesSection?
    private var selectedSensor: String = "Average System Total"
    private var fanCurveConfiguration = FanCurveConfiguration.load()
    private var temperatureSensors: [Sensor_p] = []
    private var fanCurvePrefs: PreferencesSection?
    private var fanCurveStartField: NSTextField?
    private var fanCurveCeilingField: NSTextField?
    private var fanBaselinePrefs: PreferencesSection?
    private var fanSpeedPrefs: PreferencesSection?
    private var physicalFans: [Fan] = []
    private var fanRPMFields: [String: NSTextField] = [:]
    
    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.hidState = SystemKit.shared.device.platform == .m1 ? true : false
        
        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)
        self.hidState = Store.shared.bool(key: "\(self.title)_hid", defaultValue: self.hidState)
        self.fanSpeedState = Store.shared.bool(key: "\(self.title)_speed", defaultValue: self.fanSpeedState)
        self.fansSyncState = Store.shared.bool(key: "\(self.title)_fansSync", defaultValue: self.fansSyncState)
        self.unknownSensorsState = Store.shared.bool(key: "\(self.title)_unknown", defaultValue: self.unknownSensorsState)
        self.fanValueState = FanValue(rawValue: Store.shared.string(key: "\(self.title)_fanValue", defaultValue: self.fanValueState.rawValue)) ?? .percentage
        self.selectedSensor = Store.shared.string(key: "\(self.title)_sensor", defaultValue: self.selectedSensor)

        let fanCurvePrefs = PreferencesSection([
            PreferencesRow(localizedString("Temperature fan curve"), localizedString("Automatically raise fan speed as the selected temperature rises. Enabling starts the Sensors module and requires the fan control background service."), id: "fan_curve_enabled", component: switchView(
                action: #selector(self.toggleFanCurve),
                state: self.fanCurveConfiguration.enabled
            )),
            PreferencesRow(localizedString("Temperature sensor"), id: "fan_curve_sensor", component: self.fanCurveSelectView(
                action: #selector(self.changeFanCurveSensor), items: [], selected: self.fanCurveConfiguration.sensor
            )),
            PreferencesRow(localizedString("Start increasing at"), id: "fan_curve_start", component: self.fanCurveTemperatureView(
                value: self.fanCurveConfiguration.startTemperature, id: "fan_curve_start"
            )),
            PreferencesRow(localizedString("Full speed at"), id: "fan_curve_ceiling", component: self.fanCurveTemperatureView(
                value: self.fanCurveConfiguration.ceilingTemperature, id: "fan_curve_ceiling"
            )),
            PreferencesRow(nil, localizedString("Enter whole temperatures: start 0–104 °C, maximum speed 1–105 °C. The maximum-speed temperature must be higher than the starting temperature. Press Return or leave the field to save."), component: NSView(frame: .zero)),
            PreferencesRow(nil, localizedString("With baseline hold enabled, cooling returns to the base RPM. With it disabled, cooling releases control to macOS. At 95 °C, thermal protection may exceed your maximum RPM. Sleep and quitting restore macOS control; the rule resumes on wake or relaunch."), id: "fan_curve_note", component: NSView(frame: .zero))
        ])
        self.fanCurvePrefs = fanCurvePrefs
        NotificationCenter.default.addObserver(self, selector: #selector(self.disableFanCurveFromManualControl), name: .fanCurveDisabledByManualControl, object: nil)
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: ReaderUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Fan value"), component: selectView(
                action: #selector(self.toggleFanValue),
                items: FanValues,
                selected: self.fanValueState.rawValue
            )),
            PreferencesRow(localizedString("Remember manual fan speed"), localizedString("Restores manual speed only when both fan rules are off. Manual adjustments in the fan popup turn off both rules."), component: switchView(
                action: #selector(self.toggleSpeedState),
                state: self.fanSpeedState
            )),
            PreferencesRow(localizedString("Synchronize fan's control"), component: switchView(
                action: #selector(self.toggleFansSync),
                state: self.fansSyncState
            ))
        ]))
        let baselinePrefs = PreferencesSection([
            PreferencesRow(localizedString("Keep base fan speed"), localizedString("Hold the base RPM even below the curve temperature. This switch works independently of the temperature curve and is remembered after restarting Stats."), id: "fan_baseline_enabled", component: switchView(
                action: #selector(self.toggleFanBaseline), state: self.fanCurveConfiguration.baselineEnabled
            ))
        ])
        self.fanBaselinePrefs = baselinePrefs
        self.addArrangedSubview(baselinePrefs)
        let speedPrefs = PreferencesSection(title: localizedString("Fan RPM limits"))
        self.fanSpeedPrefs = speedPrefs
        self.addArrangedSubview(speedPrefs)
        self.addArrangedSubview(fanCurvePrefs)
        
        var sensorsRows: [PreferencesRow] = [
            PreferencesRow(localizedString("Show unknown sensors"), component: switchView(
                action: #selector(self.toggleuUnknownSensors),
                state: self.unknownSensorsState
            ))
        ]
        if isARM {
            sensorsRows.append(PreferencesRow(localizedString("HID sensors"), component: switchView(
                action: #selector(self.toggleHID),
                state: self.hidState
            )))
        }
        sensorsRows.append(PreferencesRow(localizedString("Sensor to show"), id: "active_sensor", component: selectView(
            action: #selector(self.handleSelection),
            items: [],
            selected: self.selectedSensor)
        ))
        let sensorsPrefs = PreferencesSection(sensorsRows)
        self.sensorsPrefs = sensorsPrefs
        self.addArrangedSubview(sensorsPrefs)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .fanCurveDisabledByManualControl, object: nil)
    }
    
    public func load(widgets: [widget_t]) {
        self.widgets = widgets
        var sensors = self.list
        guard !sensors.isEmpty else {
            return
        }
        if !self.unknownSensorsState {
            sensors = sensors.filter({ $0.group != .unknown })
        }
        
        self.subviews.filter({ $0.identifier == NSUserInterfaceItemIdentifier("sensor") }).forEach { v in
            v.removeFromSuperview()
        }
        
        var types: [SensorType] = []
        sensors.forEach { (s: Sensor_p) in
            if !types.contains(s.type) {
                types.append(s.type)
            }
        }
        
        var buttonList: [KeyValue_t] = []
        types.forEach { (typ: SensorType) in
            let section = PreferencesSection(title: localizedString(typ.rawValue))
            section.identifier = NSUserInterfaceItemIdentifier("sensor")
            
            let filtered = sensors.filter{ $0.type == typ }
            var groups: [SensorGroup] = []
            filtered.forEach { (s: Sensor_p) in
                if !groups.contains(s.group) {
                    groups.append(s.group)
                }
            }
            groups.forEach { (group: SensorGroup) in
                filtered.filter{ $0.group == group }.forEach { (s: Sensor_p) in
                    let btn = switchView(
                        action: #selector(self.toggleSensor),
                        state: s.state
                    )
                    btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                    section.add(PreferencesRow(localizedString(s.name), component: btn))
                    buttonList.append(KeyValue_t(key: s.key, value: "\(localizedString(typ.rawValue)) - \(s.name)"))
                }
            }
            
            self.addArrangedSubview(section)
        }
        
        if let row = self.sensorsPrefs?.findRow("active_sensor") {
            self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini }))
            row.replaceComponent(with: selectView(
                action: #selector(self.handleSelection),
                items: buttonList,
                selected: self.selectedSensor
            ))
        }
    }
    
    public func setList(_ list: [Sensor_p]?) {
        guard let list else { return }
        self.list = self.unknownSensorsState ? list : list.filter({ $0.group != .unknown })
        self.temperatureSensors = self.list.filter { $0.type == .temperature }
        self.physicalFans = list.compactMap { $0 as? Fan }.filter { !$0.isComputed && $0.maxSpeed > $0.minSpeed && $0.maxSpeed > 1 }.sorted { $0.id < $1.id }
        self.rebuildFanRPMControls()
        if !self.temperatureSensors.contains(where: { $0.key == self.fanCurveConfiguration.sensor }),
           let fallback = self.temperatureSensors.first(where: { $0.key == "Hottest CPU" }) ??
                self.temperatureSensors.first(where: { $0.group == .CPU }) ?? self.temperatureSensors.first {
            self.fanCurveConfiguration.sensor = fallback.key
            self.fanCurveConfiguration.save()
        }
        self.refreshFanCurveControls()
        self.load(widgets: self.widgets)
    }

    private func fanCurveSelectView(action: Selector, items: [KeyValue_t], selected: String) -> NSPopUpButton {
        let view = self.selectView(action: action, items: items, selected: selected)
        view.widthAnchor.constraint(equalToConstant: action == #selector(self.changeFanCurveSensor) ? 235 : 100).isActive = true
        return view
    }

    private func fanCurveTemperatureView(value: Int, id: String) -> NSView {
        let field = NSTextField(frame: .zero)
        field.stringValue = "\(value)"
        field.identifier = NSUserInterfaceItemIdentifier(id)
        field.delegate = self
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.alignment = .right
        field.font = NSFont.systemFont(ofSize: 13)
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        field.setAccessibilityLabel(localizedString(id == "fan_curve_start" ? "Start increasing at" : "Full speed at"))
        if id == "fan_curve_start" {
            self.fanCurveStartField = field
        } else {
            self.fanCurveCeilingField = field
        }

        let view = NSStackView(views: [field, NSTextField(labelWithString: "°C")])
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 5
        return view
    }

    private func rebuildFanRPMControls() {
        guard let section = self.fanSpeedPrefs else { return }
        for id in self.fanRPMFields.keys { section.delete(id) }
        self.fanRPMFields.removeAll()
        section.delete("fan_rpm_empty")
        if self.physicalFans.isEmpty {
            section.add(PreferencesRow(nil, localizedString("No controllable fans detected."), id: "fan_rpm_empty", component: NSView(frame: .zero)))
        }
        for fan in self.physicalFans {
            let limits = self.fanCurveConfiguration.limits(for: fan)
            for (kind, title, value) in [("base", "Base fan speed", limits.baseRPM), ("maximum", "Maximum fan speed", limits.maximumRPM)] {
                let id = "\(kind)_\(fan.id)"
                let field = NSTextField(string: "\(value)")
                field.identifier = NSUserInterfaceItemIdentifier(id)
                field.delegate = self
                field.bezelStyle = .roundedBezel
                field.alignment = .right
                field.widthAnchor.constraint(equalToConstant: 80).isActive = true
                let label = "\(localizedString(fan.name)) · \(localizedString(title))"
                field.setAccessibilityLabel(label)
                self.fanRPMFields[id] = field
                let view = NSStackView(views: [field, NSTextField(labelWithString: "RPM")])
                view.spacing = 5
                let lower = min(max(1000, Int(fan.minSpeed)), Int(fan.maxSpeed))
                section.add(PreferencesRow(label, "\(lower)–\(Int(fan.maxSpeed)) RPM", id: id, component: view))
            }
        }
    }

    private func refreshFanCurveControls() {
        guard let fanCurvePrefs else { return }
        if let row = fanCurvePrefs.findRow("fan_curve_enabled"),
           let toggle = row.arrangedSubviews.last as? NSSwitch {
            toggle.state = self.fanCurveConfiguration.enabled ? .on : .off
        }
        let sensorOptions = self.temperatureSensors.map { sensor in
            KeyValue_t(key: sensor.key, value: "\(localizedString(sensor.name)) (\(localizedString(sensor.group.rawValue)))")
        }
        let controls: [(String, Selector, [KeyValue_t], String)] = [
            ("fan_curve_sensor", #selector(self.changeFanCurveSensor), sensorOptions, self.fanCurveConfiguration.sensor)
        ]
        controls.forEach { (id, action, items, selected) in
            guard let row = fanCurvePrefs.findRow(id) else { return }
            row.replaceComponent(with: self.fanCurveSelectView(action: action, items: items, selected: selected))
        }
        if let row = self.fanBaselinePrefs?.findRow("fan_baseline_enabled"), let toggle = row.arrangedSubviews.last as? NSSwitch {
            toggle.state = self.fanCurveConfiguration.baselineEnabled ? .on : .off
        }
        for fan in self.physicalFans {
            let limits = self.fanCurveConfiguration.limits(for: fan)
            for (id, value) in [("base_\(fan.id)", limits.baseRPM), ("maximum_\(fan.id)", limits.maximumRPM)] {
                if let field = self.fanRPMFields[id], field.currentEditor() == nil { field.stringValue = "\(value)" }
            }
        }
        if self.fanCurveStartField?.currentEditor() == nil {
            self.fanCurveStartField?.stringValue = "\(self.fanCurveConfiguration.startTemperature)"
        }
        if self.fanCurveCeilingField?.currentEditor() == nil {
            self.fanCurveCeilingField?.stringValue = "\(self.fanCurveConfiguration.ceilingTemperature)"
        }
    }

    private func saveFanCurveConfiguration() {
        self.fanCurveConfiguration.normalize()
        self.fanCurveConfiguration.save()
        self.refreshFanCurveControls()
        self.fanCurveChanged?(self.fanCurveConfiguration)
    }

    func disableFanCurve() {
        guard self.fanCurveConfiguration.isActive else { return }
        self.fanCurveConfiguration.enabled = false
        self.fanCurveConfiguration.baselineEnabled = false
        self.saveFanCurveConfiguration()
    }

    @objc private func toggleFanCurve(_ sender: NSControl) {
        self.toggleFanPolicy(sender, baseline: false)
    }

    @objc private func toggleFanBaseline(_ sender: NSControl) {
        self.toggleFanPolicy(sender, baseline: true)
    }

    private func toggleFanPolicy(_ sender: NSControl, baseline: Bool) {
        let enabled = controlState(sender)
        if enabled && !MacFanProBridge.shared.isInstalled {
            (sender as? NSSwitch)?.state = .off
            let alert = NSAlert()
            alert.messageText = localizedString("Fan control service required")
            alert.informativeText = localizedString("Stats needs one-time administrator authorization to install the fan control service. Its temporary setup helper will be removed afterwards.")
            alert.addButton(withTitle: localizedString("Install fan service"))
            alert.addButton(withTitle: localizedString("Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                MacFanProBridge.shared.installService { [weak self] success, details in
                    guard let self else { return }
                    if success {
                        if baseline { self.fanCurveConfiguration.baselineEnabled = true }
                        else { self.fanCurveConfiguration.enabled = true }
                        self.saveFanCurveConfiguration()
                    } else {
                        let result = NSAlert()
                        result.messageText = localizedString("Fan service setup did not finish")
                        result.informativeText = details ?? localizedString("You can try again from this setting.")
                        result.addButton(withTitle: localizedString("OK"))
                        result.runModal()
                    }
                }
            }
            return
        }
        if baseline { self.fanCurveConfiguration.baselineEnabled = enabled }
        else { self.fanCurveConfiguration.enabled = enabled }
        self.saveFanCurveConfiguration()
    }

    @objc private func changeFanCurveSensor(_ sender: NSPopUpButton) {
        guard let key = sender.selectedItem?.representedObject as? String else { return }
        self.fanCurveConfiguration.sensor = key
        self.saveFanCurveConfiguration()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }
        if id.hasPrefix("base_") || id.hasPrefix("maximum_") {
            self.saveFanRPM(field, id: id)
            return
        }
        guard id == "fan_curve_start" || id == "fan_curve_ceiling" else { return }

        let isStart = id == "fan_curve_start"
        let previous = isStart ? self.fanCurveConfiguration.startTemperature : self.fanCurveConfiguration.ceilingTemperature
        let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Int(input)
        let valid = value.map { temperature in
            isStart
                ? FanCurveConfiguration.startTemperatureRange.contains(temperature) && temperature < self.fanCurveConfiguration.ceilingTemperature
                : FanCurveConfiguration.ceilingTemperatureRange.contains(temperature) && temperature > self.fanCurveConfiguration.startTemperature
        } ?? false
        guard valid, let value else {
            field.stringValue = "\(previous)"
            let alert = NSAlert()
            alert.messageText = localizedString("Invalid fan curve temperature")
            alert.informativeText = localizedString("Enter whole temperatures: start 0–104 °C, maximum speed 1–105 °C. The maximum-speed temperature must be higher than the starting temperature.")
            alert.addButton(withTitle: localizedString("OK"))
            if let window = self.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }
        field.stringValue = "\(value)"
        guard value != previous else { return }
        if isStart {
            self.fanCurveConfiguration.startTemperature = value
        } else {
            self.fanCurveConfiguration.ceilingTemperature = value
        }
        self.saveFanCurveConfiguration()
    }

    private func saveFanRPM(_ field: NSTextField, id: String) {
        guard let fanID = Int(id.split(separator: "_").last ?? ""),
              let fan = self.physicalFans.first(where: { $0.id == fanID }) else { return }
        var limits = self.fanCurveConfiguration.limits(for: fan)
        let isBase = id.hasPrefix("base_")
        let previous = isBase ? limits.baseRPM : limits.maximumRPM
        let lower = min(max(1000, Int(fan.minSpeed)), Int(fan.maxSpeed))
        let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let value, (lower...Int(fan.maxSpeed)).contains(value),
              isBase ? value <= limits.maximumRPM : value >= limits.baseRPM else {
            field.stringValue = "\(previous)"
            let alert = NSAlert()
            alert.messageText = localizedString("Invalid fan RPM")
            alert.informativeText = "\(localizedString("Enter a whole RPM within the fan's range. The maximum RPM must be at least the base RPM.")) (\(lower)–\(Int(fan.maxSpeed)) RPM)"
            alert.addButton(withTitle: localizedString("OK"))
            if let window = self.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        field.stringValue = "\(value)"
        if isBase { limits.baseRPM = value } else { limits.maximumRPM = value }
        self.fanCurveConfiguration.fanSpeeds[String(fanID)] = limits
        self.saveFanCurveConfiguration()
    }

    @objc private func disableFanCurveFromManualControl() {
        DispatchQueue.main.async {
            self.fanCurveConfiguration = FanCurveConfiguration.load()
            self.refreshFanCurveControls()
            self.fanCurveChanged?(self.fanCurveConfiguration)
        }
    }

    @objc private func toggleSensor(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)", value: controlState(sender))
        self.callback()
    }
    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(self.fanCurveConfiguration.isActive ? 1 : value)
    }
    @objc private func toggleSpeedState(_ sender: NSControl) {
        self.fanSpeedState = controlState(sender)
        Store.shared.set(key: "\(self.title)_speed", value: self.fanSpeedState)
        self.callback()
    }
    @objc private func toggleHID(_ sender: NSControl) {
        self.hidState = controlState(sender)
        Store.shared.set(key: "\(self.title)_hid", value: self.hidState)
        self.HIDcallback()
    }
    @objc private func toggleFansSync(_ sender: NSControl) {
        self.fansSyncState = controlState(sender)
        Store.shared.set(key: "\(self.title)_fansSync", value: self.fansSyncState)
    }
    @objc private func toggleuUnknownSensors(_ sender: NSControl) {
        self.unknownSensorsState = controlState(sender)
        Store.shared.set(key: "\(self.title)_unknown", value: self.unknownSensorsState)
        self.unknownCallback()
    }
    @objc private func toggleFanValue(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = FanValue(rawValue: key) {
            self.fanValueState = value
            Store.shared.set(key: "\(self.title)_fanValue", value: self.fanValueState.rawValue)
            self.callback()
        }
    }
    @objc private func handleSelection(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.representedObject as? String else { return }
        self.selectedSensor = id
        Store.shared.set(key: "\(self.title)_sensor", value: self.selectedSensor)
        self.selectedHandler(self.selectedSensor)
    }
}
