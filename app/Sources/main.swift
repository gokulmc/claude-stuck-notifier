// Nudge — menu-bar app that makes Claude Code "waiting" notifications clickable.
// Compiled with -swift-version 5 to avoid strict-concurrency friction.

import AppKit
import UserNotifications

final class Controller: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    struct Waiting { let id: String; let subtitle: String; let message: String; let cwd: String; let added: Date }

    private var statusItem: NSStatusItem!
    private var waiting: [Waiting] = []
    private let center = UNUserNotificationCenter.current()
    private var authDenied = false

    private let vsID = "com.microsoft.VSCode"
    private let staleAfter: TimeInterval = 20 * 60   // auto-drop entries older than 20 min

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ note: Notification) {
        // Single instance. The LaunchAgent launches Nudge with "--agent" and is
        // authoritative: it clears any stray instances and stays. A stray (e.g.
        // spawned by `open nudge://` before the agent was up) defers to whatever
        // is already running, so we never leave an unmanaged instance.
        let isAgent = CommandLine.arguments.contains("--agent")
        let mePID = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.gokulmc.nudge")
            .filter { $0.processIdentifier != mePID }
        if isAgent {
            others.forEach { $0.terminate() }
        } else if !others.isEmpty {
            NSApp.terminate(nil); return
        }

        NSApp.setActivationPolicy(.accessory) // menu-bar only (also LSUIElement in Info.plist)
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshAuth()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let img = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Nudge")?
                .withSymbolConfiguration(cfg)
            img?.isTemplate = true
            b.image = img
            b.imagePosition = .imageLeading
        }
        rebuildMenu()

        // Safety-net sweep: drop entries the user never cleared and that are old.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.sweepStale()
        }
    }

    // MARK: - URL scheme (modern delegate, no Carbon)
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        func v(_ k: String) -> String { comps.queryItems?.first(where: { $0.name == k })?.value ?? "" }

        switch comps.host {
        case "notify":
            let title = v("title").isEmpty ? "Claude Code" : v("title")
            let message = v("message").isEmpty ? "Needs your attention" : v("message")
            let cwd = v("cwd")
            let w = Waiting(id: UUID().uuidString, subtitle: v("subtitle"),
                            message: message, cwd: cwd, added: Date())
            if !cwd.isEmpty { waiting.removeAll { $0.cwd == cwd } } // de-dupe by project
            waiting.append(w)
            postNotification(title: title, w: w)
            DispatchQueue.main.async { self.rebuildMenu() }
        case "clear":                       // a window is no longer waiting (user responded)
            clearProject(cwd: v("cwd"))
        case "clearall":
            clearAllEntries()
        default:
            return
        }
    }

    private func postNotification(title: String, w: Waiting) {
        let c = UNMutableNotificationContent()
        c.title = title
        if !w.subtitle.isEmpty { c.subtitle = w.subtitle }
        c.body = w.message
        c.sound = .default
        c.userInfo = ["cwd": w.cwd, "id": w.id]
        center.add(UNNotificationRequest(identifier: w.id, content: c, trigger: nil))
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let cwd = info["cwd"] as? String ?? ""
        let id = info["id"] as? String
        DispatchQueue.main.async {
            self.focusVSCode(cwd: cwd)
            if let id = id { self.remove(id: id) }
        }
        completionHandler()
    }

    // MARK: - Focus the right VS Code window
    private func focusVSCode(cwd: String) {
        let ws = NSWorkspace.shared

        // Only run `code <cwd>` for a real project folder. For a folder-less
        // session cwd is the home dir (or empty/root); running `code ~` would
        // wrongly open home as a workspace, so we just bring VS Code forward.
        let home = NSHomeDirectory()
        let isProject = !cwd.isEmpty && cwd != home && cwd != "/"
        if isProject, let appURL = ws.urlForApplication(withBundleIdentifier: vsID) {
            let cli = appURL.appendingPathComponent("Contents/Resources/app/bin/code")
            if FileManager.default.fileExists(atPath: cli.path) {
                let p = Process()
                p.executableURL = cli
                p.arguments = [cwd]
                try? p.run()
            }
        }

        // Always bring VS Code to the front — the only action for a folder-less
        // session, and a backstop otherwise.
        if let vs = NSRunningApplication.runningApplications(withBundleIdentifier: vsID).first {
            vs.activate()
        } else if let appURL = ws.urlForApplication(withBundleIdentifier: vsID) {
            ws.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // MARK: - Menu actions
    @objc private func focusItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let w = waiting.first(where: { $0.id == id }) else { return }
        focusVSCode(cwd: w.cwd)
        remove(id: id)
    }

    @objc private func clearAll() { clearAllEntries() }

    @objc private func openNotificationSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Entry bookkeeping
    private func remove(id: String) {
        waiting.removeAll { $0.id == id }
        center.removeDeliveredNotifications(withIdentifiers: [id])
        rebuildMenu()
    }

    private func clearProject(cwd: String) {
        guard !cwd.isEmpty else { return }
        let ids = waiting.filter { $0.cwd == cwd }.map { $0.id }
        guard !ids.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: ids)
        waiting.removeAll { $0.cwd == cwd }
        DispatchQueue.main.async { self.rebuildMenu() }
    }

    private func clearAllEntries() {
        center.removeDeliveredNotifications(withIdentifiers: waiting.map { $0.id })
        waiting.removeAll()
        DispatchQueue.main.async { self.rebuildMenu() }
    }

    private func sweepStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        let stale = waiting.filter { $0.added < cutoff }
        guard !stale.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: stale.map { $0.id })
        waiting.removeAll { $0.added < cutoff }
        rebuildMenu()
    }

    private func refreshAuth() {
        center.getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                self?.authDenied = (s.authorizationStatus == .denied)
                self?.rebuildMenu()
            }
        }
    }

    // MARK: - Menu
    private func rebuildMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: waiting.isEmpty ? "No Claude windows waiting" : "\(waiting.count) waiting",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !waiting.isEmpty {
            menu.addItem(.separator())
            for w in waiting {
                let label = w.subtitle.isEmpty ? w.message : "\(w.subtitle) — \(w.message)"
                let item = NSMenuItem(title: truncate(label, 60), action: #selector(focusItem(_:)), keyEquivalent: "")
                item.representedObject = w.id
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear all", action: #selector(clearAll), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }

        if authDenied {
            menu.addItem(.separator())
            let s = NSMenuItem(title: "⚠ Notifications disabled — open Settings",
                               action: #selector(openNotificationSettings), keyEquivalent: "")
            s.target = self
            menu.addItem(s)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Nudge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.title = waiting.isEmpty ? "" : "  \(waiting.count)"
    }

    private func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }
}

let app = NSApplication.shared
let controller = Controller()
app.delegate = controller
app.run()
