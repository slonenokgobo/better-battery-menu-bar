import SwiftUI
import AppKit
import IOKit.ps
import UserNotifications
import ServiceManagement
import Combine

@main
struct BatteryBeaconApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = StatusBarController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class StatusBarController: NSObject, NSApplicationDelegate {
    private let model = BatteryModel()
    private var item: NSStatusItem!
    private var panel: NSPanel!
    private var subscription: AnyCancellable?
    private var lowBatteryPulse: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        subscription = Publishers.CombineLatest4(model.$percent, model.$onPower, model.$charging, model.$threshold)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] percent, onPower, charging, threshold in
                let lowBattery = percent.map { $0 <= threshold } ?? false
                self?.item.button?.image = menuBarBattery(percent: percent, onPower: onPower, charging: charging, lowBattery: lowBattery)
                self?.updateLowBatteryPulse(active: lowBattery)
                let state = charging ? "Charging" : onPower ? "Connected to power" : "On battery"
                self?.item.button?.toolTip = percent.map { "BatteryBeacon: \($0)% · \(state)" } ?? "BatteryBeacon"
            }
        panel = MenuPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: BatteryPanel(model: model))
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        panel.setContentSize(host.fittingSize)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hidePanel() }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.hidePanel(); return nil }
            if event.type != .keyDown, event.window !== self.panel, event.window !== self.item.button?.window { self.hidePanel() }
            return event
        }
    }
    private func updateLowBatteryPulse(active: Bool) {
        guard active, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            lowBatteryPulse?.invalidate()
            lowBatteryPulse = nil
            return
        }
        guard lowBatteryPulse == nil else { return }
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let button = self.item.button else { return }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let borderPulse = reduceMotion ? 0 : CGFloat((1 - cos(elapsed * .pi / 1.1)) / 2)
            button.image = menuBarBattery(percent: self.model.percent, onPower: self.model.onPower,
                                          charging: self.model.charging, lowBattery: true, borderPulse: borderPulse)
            if reduceMotion { self.updateLowBatteryPulse(active: false) }
        }
        lowBatteryPulse = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func togglePanel() {
        if panel.isVisible { hidePanel(); return }
        guard let button = item.button, let window = button.window else { return }
        model.checkPermissions()
        model.refresh()
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        panel.contentView?.layoutSubtreeIfNeeded()
        if let size = panel.contentView?.fittingSize { panel.setContentSize(size) }
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(anchor.midX - panel.frame.width / 2, screen.minX + 6), screen.maxX - panel.frame.width - 6)
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - panel.frame.height - 6))
        item.button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func hidePanel() {
        panel.orderOut(nil)
        item.button?.highlight(false)
    }
    func applicationWillTerminate(_ notification: Notification) {
        lowBatteryPulse?.invalidate()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

private struct MenuSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.masksToBounds = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private func menuBarBattery(percent: Int?, onPower: Bool, charging: Bool, lowBattery: Bool, borderPulse: CGFloat = 0) -> NSImage {
    let tint = lowBattery ? NSColor(srgbRed: 0.70, green: 0.10, blue: 0.17, alpha: 1) : .black
    let scale: CGFloat = lowBattery ? 1.125 : 1
    let imageSize = NSSize(width: (onPower ? 40 : 29) * scale, height: 16 * scale)
    let image = NSImage(size: imageSize, flipped: false) { _ in
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
        let body = NSBezierPath(roundedRect: NSRect(x: lowBattery ? 0.5 : 0, y: 1, width: lowBattery ? 25.5 : 26, height: 14), xRadius: 4, yRadius: 4)
        let trackColor = lowBattery ? tint : tint.withAlphaComponent(0.35)
        trackColor.setFill()
        body.fill()
        if lowBattery {
            let borderColor = NSColor.white.blended(withFraction: borderPulse, of: .systemRed) ?? .white
            borderColor.setStroke()
            body.lineWidth = 1
            body.stroke()
        }
        NSBezierPath(roundedRect: NSRect(x: 27, y: 5.5, width: 1.5, height: 5), xRadius: 0.75, yRadius: 0.75).fill()
        if !lowBattery {
            let fillWidth = 26 * CGFloat(min(100, max(0, percent ?? 0))) / 100
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            tint.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 1, width: fillWidth, height: 14)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let text = percent.map(String.init) ?? "—"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: lowBattery ? NSColor.white : NSColor.black
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        if !lowBattery {
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
        }
        (text as NSString).draw(at: NSPoint(x: (26 - size.width) / 2, y: (16 - size.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        if lowBattery && onPower && charging {
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 36.8, y: 14))
            bolt.line(to: NSPoint(x: 31.5, y: 7))
            bolt.line(to: NSPoint(x: 35, y: 7))
            bolt.line(to: NSPoint(x: 34.2, y: 2))
            bolt.line(to: NSPoint(x: 39.5, y: 9))
            bolt.line(to: NSPoint(x: 36, y: 9))
            bolt.close()
            tint.setFill()
            bolt.fill()
            NSColor.white.setStroke()
            bolt.lineWidth = 0.8
            bolt.lineJoinStyle = .round
            bolt.stroke()
        } else if onPower {
            let symbol = charging ? "bolt.fill" : "plug.fill"
            var configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            if lowBattery {
                configuration = configuration.applying(.init(paletteColors: [tint]))
            }
            if let badge = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                badge.draw(in: NSRect(x: 31, y: 2, width: 9, height: 12))
            }
        }
        return true
    }
    image.isTemplate = !lowBattery
    return image
}

final class BatteryModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var percent: Int?
    @Published var onPower = false
    @Published var charging = false
    @Published var minutes: Int?
    @Published var message = "Enable notifications to receive battery alerts."
    @Published var notificationsAllowed = false
    @Published var loginEnabled = false
    @Published var threshold: Int = UserDefaults.standard.object(forKey: "threshold") as? Int ?? 10 {
        didSet { UserDefaults.standard.set(threshold, forKey: "threshold"); refresh() }
    }
    private var policy = AlertPolicy()
    private var reminderTimer: Timer?
    private var lastNotificationID = "low-battery"
    private var source: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let model = Unmanaged<BatteryModel>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { model.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh(); self?.checkPermissions() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.checkPermissions() })
        refresh()
        checkPermissions()
    }
    deinit {
        reminderTimer?.invalidate()
        if let source { CFRunLoopSourceInvalidate(source) }
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }
    func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { percent = nil; reminderTimer?.invalidate(); reminderTimer = nil; return }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            percent = min(100, Swift.max(0, Int(Double(current) / Double(max) * 100)))
            onPower = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            charging = d[kIOPSIsChargingKey] as? Bool ?? false
            let estimate = d[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            minutes = estimate.flatMap { $0 > 0 ? $0 : nil }
            if onPower || (percent ?? 100) > threshold {
                reminderTimer?.invalidate()
                reminderTimer = nil
            }
            if let percent, policy.evaluate(percent: percent, onPower: onPower, threshold: threshold) {
                sendNotification()
                reminderTimer?.invalidate()
                let timer = Timer(timeInterval: AlertPolicy.repeatInterval, repeats: false) { [weak self] _ in self?.refresh() }
                reminderTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
            return
        }
        percent = nil
        reminderTimer?.invalidate()
        reminderTimer = nil
    }
    func checkPermissions() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
                self.message = self.notificationsAllowed ? "Alerts are enabled. Focus may silence notifications." : "Enable notifications to receive battery alerts."
                if self.notificationsAllowed { self.refresh() }
            }
        }
    }
    func enableNotifications() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error { self.message = error.localizedDescription }
                else if !granted {
                    self.message = "Allow BatteryBeacon in System Settings → Notifications."
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
                self.checkPermissions()
            }
        }
    }
    func sendNotification() {
        guard notificationsAllowed else { policy.retry(); return }
        let content = UNMutableNotificationContent()
        content.title = "Battery is low"
        content.body = "Battery at \(percent ?? threshold)%. Connect your charger."
        content.sound = .default
        center.removeDeliveredNotifications(withIdentifiers: [lastNotificationID])
        let identifier = "low-battery-\(UUID().uuidString)"
        lastNotificationID = identifier
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            DispatchQueue.main.async {
                if let error { self.message = error.localizedDescription; self.policy.retry() }
            }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { message = "Approve BatteryBeacon in System Settings → General → Login Items." }
        } catch { message = error.localizedDescription }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct BatteryPanel: View {
    @ObservedObject var model: BatteryModel
    private var tint: Color { (model.percent ?? 100) <= model.threshold && !model.onPower ? .orange : .green }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.primary.opacity(0.09), lineWidth: 4)
                    Circle().trim(from: 0, to: Double(model.percent ?? 0) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(model.percent.map { "\($0)%" } ?? "—")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }.frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Host.current().localizedName ?? "Your Mac").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.percent == nil ? "No internal battery" : model.charging ? "Charging" : model.onPower ? "Connected to power" : "Running on battery")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let minutes = model.minutes {
                        Text(model.charging ? "Full in about \(batteryDuration(minutes))" : "About \(batteryDuration(minutes)) remaining")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }.padding(14)
            separator
            Text("Battery alerts").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 5)
            HStack {
                Image(systemName: "bell.badge").frame(width: 18)
                Text("Warn me at")
                Spacer()
                Menu {
                    ForEach(Array(stride(from: 5, through: 90, by: 5)), id: \.self) { value in
                        Button { model.threshold = value } label: {
                            if model.threshold == value { Label("\(value)%", systemImage: "checkmark") }
                            else { Text("\(value)%") }
                        }
                    }
                } label: {
                    HStack(spacing: 5) { Text("\(model.threshold)%"); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)) }
                }.menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal, 14).frame(height: 30)
            menuRow("Launch at login", symbol: model.loginEnabled ? "checkmark" : "", action: { model.setLogin(!model.loginEnabled) })
            Text(model.message).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 11)
            separator
            if !model.notificationsAllowed {
                menuRow("Enable notifications…", symbol: "bell", action: model.enableNotifications)
                    .padding(.vertical, 4)
                separator
            }
            menuRow("Quit BatteryBeacon", symbol: "", action: { NSApplication.shared.terminate(nil) })
                .padding(.vertical, 5)
        }
        .font(.system(size: 13))
        .frame(width: 310)
        .background(MenuSurface())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
    }
    private var separator: some View { Divider().padding(.horizontal, 10) }
    private func menuRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol.isEmpty ? "checkmark" : symbol).opacity(symbol.isEmpty ? 0 : 1).frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
        }.buttonStyle(MenuRowStyle()).padding(.horizontal, 6)
    }
}

private struct MenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration, enabled: enabled)
    }
    private struct MenuRowBody: View {
        let configuration: ButtonStyleConfiguration
        let enabled: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(enabled && (hovered || configuration.isPressed) ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 5).fill(enabled && (hovered || configuration.isPressed) ? Color.accentColor : .clear))
                .opacity(enabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}

private func batteryDuration(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    guard hours > 0 else { return "\(minutes) min" }
    let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
    return remainder == 0 ? hourText : "\(hourText) \(remainder) min"
}
