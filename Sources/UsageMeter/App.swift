import AppKit
import ServiceManagement

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--check") {
            runCheck()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// `UsageMeter --check`: fetch both services once and print what the
    /// menu bar and menu would show. Useful for diagnosing auth issues.
    private static func runCheck() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for kind in ServiceKind.allCases {
                let state = await fetchUsage(for: kind)
                if case .notConfigured = state {
                    print("\(kind.displayName): not configured (no \(kind.cliName) login found) — hidden from the menu")
                    continue
                }
                print("\(kind.displayName): \(Fmt.statusTitle(kind: kind, state: state))")
                switch state {
                case .ok(let snap):
                    func describe(_ label: String, _ w: Window) {
                        let reset = w.resetsAt.map { ", resets \(Fmt.fullTime($0))" } ?? ""
                        print("  \(label)  \(Fmt.percent(w.remainingPercent)) left\(reset)")
                    }
                    if let five = snap.fiveHour { describe("5-hour", five) }
                    if let weekly = snap.weekly { describe("Weekly", weekly) }
                    if snap.primary == nil { print("  (no active limits reported)") }
                case .error(let message):
                    print("  error: \(message)")
                case .loading, .notConfigured:
                    break
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let selectedServiceKey = "selectedService"

    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var states: [ServiceKind: ServiceState] = [.claude: .loading, .codex: .loading]
    private var refreshing = false

    var selectedService: ServiceKind {
        get {
            ServiceKind(rawValue: UserDefaults.standard.string(forKey: selectedServiceKey) ?? "")
                ?? .claude
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedServiceKey)
            updateStatusTitle()
            rebuildMenu()
        }
    }

    /// Services with a CLI login on this machine. Unconfigured ones are hidden.
    private var configuredServices: [ServiceKind] {
        ServiceKind.allCases.filter { (states[$0] ?? .loading).isConfigured }
    }

    /// What the menu bar shows: the user's choice if it's configured, otherwise
    /// the first configured service. The stored preference is left untouched so
    /// it comes back if the user later logs into that CLI.
    private var effectiveService: ServiceKind? {
        let configured = configuredServices
        if configured.contains(selectedService) { return selectedService }
        return configured.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusTitle()
        rebuildMenu()
        refresh()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refreshTimer?.tolerance = 30
    }

    // MARK: - Refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task { @MainActor in
            async let claude = fetchUsage(for: .claude)
            async let codex = fetchUsage(for: .codex)
            states[.claude] = await claude
            states[.codex] = await codex
            refreshing = false
            updateStatusTitle()
            rebuildMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    // MARK: - UI

    private func updateStatusTitle() {
        guard let kind = effectiveService else {
            statusItem.button?.title = "◔"
            return
        }
        statusItem.button?.title = Fmt.statusTitle(kind: kind, state: states[kind] ?? .loading)
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let configured = configuredServices
        if configured.isEmpty {
            let none = NSMenuItem(
                title: "No Claude Code or Codex login found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            let hint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            hint.attributedTitle = NSAttributedString(
                string: "Sign in via the claude or codex CLI, then Refresh.",
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
            menu.addItem(hint)
        }

        // A selection checkmark only makes sense with more than one service.
        let selectable = configured.count > 1
        for kind in configured {
            let state = states[kind] ?? .loading

            let header = NSMenuItem(
                title: "", action: selectable ? #selector(selectService(_:)) : nil,
                keyEquivalent: "")
            header.target = selectable ? self : nil
            header.representedObject = kind.rawValue
            header.state = selectable && kind == effectiveService ? .on : .off
            header.attributedTitle = serviceHeaderTitle(kind: kind, state: state)
            menu.addItem(header)

            for detail in serviceDetailLines(kind: kind, state: state) {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = detail
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let login = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = Bundle.main.bundleIdentifier != nil
        menu.addItem(login)

        let refreshItem = NSMenuItem(
            title: "Refresh Now", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit UsageMeter", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func serviceHeaderTitle(kind: ServiceKind, state: ServiceState) -> NSAttributedString {
        let summary: String
        switch state {
        case .loading: summary = "loading…"
        case .error: summary = "unavailable"
        case .notConfigured: summary = ""  // hidden from the menu; not rendered
        case .ok(let snap):
            if let w = snap.primary {
                let suffix = snap.primaryIsWeekly ? " (weekly)" : ""
                summary = "\(Fmt.percent(w.remainingPercent)) left\(suffix)"
            } else {
                summary = "no active limits"
            }
        }
        let title = NSMutableAttributedString(
            string: kind.displayName,
            attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(
            string: "   \(summary)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        return title
    }

    private func serviceDetailLines(kind: ServiceKind, state: ServiceState) -> [NSAttributedString] {
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        switch state {
        case .loading, .notConfigured:
            return []
        case .error(let message):
            return [NSAttributedString(string: "      \(message)", attributes: detailAttrs)]
        case .ok(let snap):
            func line(_ label: String, _ w: Window) -> NSAttributedString {
                var s = "      \(label)   "
                if let reset = w.resetsAt {
                    s += "resets \(Fmt.fullTime(reset))   (\(Fmt.percent(w.remainingPercent)) left)"
                } else {
                    s += "\(Fmt.percent(w.remainingPercent)) left"
                }
                return NSAttributedString(string: s, attributes: detailAttrs)
            }
            var lines: [NSAttributedString] = []
            if let five = snap.fiveHour { lines.append(line("5-hour", five)) }
            if let weekly = snap.weekly { lines.append(line("Weekly", weekly)) }
            return lines
        }
    }

    // MARK: - Actions

    @objc private func selectService(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ServiceKind(rawValue: raw) else { return }
        selectedService = kind
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login toggle failed: \(error)")
        }
        rebuildMenu()
    }
}
