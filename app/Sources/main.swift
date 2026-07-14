// Nudge — menu-bar app that makes Claude Code "waiting" notifications clickable.
// Compiled with -swift-version 5 to avoid strict-concurrency friction.

import AppKit
import UserNotifications

final class Controller: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    struct Waiting { let id: String; let subtitle: String; let message: String; let cwd: String }

    private var statusItem: NSStatusItem!
    private var waiting: [Waiting] = []
    private let center = UNUserNotificationCenter.current()
    private var authDenied = false

    private let vsID = "com.microsoft.VSCode"

    // MARK: - Lifecycle
    func applicationDidFinishLaunching(_ note: Notification) {
        // Single instance: if another Nudge is already running (e.g. LaunchAgent +
        // manual open), bow out so we don't get duplicate menu-bar icons.
        let mePID = NSRunningApplication.current.processIdentifier
        let dupes = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.gokulmc.nudge")
            .filter { $0.processIdentifier != mePID }
        if !dupes.isEmpty { NSApp.terminate(nil); return }

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
    }

    // MARK: - URL scheme (modern delegate, no Carbon)
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handle)
    }

    private func handle(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host == "notify" else { return }
        let q = comps.queryItems ?? []
        func v(_ k: String) -> String { q.first(where: { $0.name == k })?.value ?? "" }

        let title = v("title").isEmpty ? "Claude Code" : v("title")
        let subtitle = v("subtitle")
        let message = v("message").isEmpty ? "Needs your attention" : v("message")
        let cwd = v("cwd")
        let w = Waiting(id: UUID().uuidString, subtitle: subtitle, message: message, cwd: cwd)

        if !cwd.isEmpty { waiting.removeAll { $0.cwd == cwd } } // de-dupe by project
        waiting.append(w)
        postNotification(title: title, w: w)
        DispatchQueue.main.async { self.rebuildMenu() }
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
        completionHandler([.banner, .list, .sound]) // show even if we're active; also land in Notification Center
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
        if !cwd.isEmpty, let appURL = ws.urlForApplication(withBundleIdentifier: vsID) {
            let cli = appURL.appendingPathComponent("Contents/Resources/app/bin/code")
            if FileManager.default.fileExists(atPath: cli.path) {
                let p = Process()
                p.executableURL = cli
                p.arguments = [cwd]
                try? p.run()
            }
        }
        if let vs = NSRunningApplication.runningApplications(withBundleIdentifier: vsID).first {
            vs.activate()
        } else if let appURL = ws.urlForApplication(withBundleIdentifier: vsID) {
            ws.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // MARK: - Menu
    @objc private func focusItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let w = waiting.first(where: { $0.id == id }) else { return }
        focusVSCode(cwd: w.cwd)
        remove(id: id)
    }

    @objc private func clearAll() {
        center.removeDeliveredNotifications(withIdentifiers: waiting.map { $0.id })
        waiting.removeAll()
        rebuildMenu()
    }

    @objc private func openNotificationSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func remove(id: String) {
        waiting.removeAll { $0.id == id }
        center.removeDeliveredNotifications(withIdentifiers: [id])
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
