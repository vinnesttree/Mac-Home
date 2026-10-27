import AppKit
import SwiftUI

/// Owns the windows and decides what is on screen: the home screen, the web player, another app, or the desktop.
final class AppController: NSObject, NSApplicationDelegate {
    private enum Mode {
        case launcher, player, external, desktop
    }

    private static let playerKey = "MacHome.player"

    let launcher = LauncherModel()
    lazy var toast = Toast()
    private(set) var player: WebPlayer?
    private let store = ConfigStore()
    private let synth = EventSynth()
    private var gamepad: GamepadMonitor!
    private var router: InputRouter!
    private var launcherWindow: FullScreenWindow!
    private var mode = Mode.launcher
    /// Gamepad profile for each app MacHome opened, by bundle identifier.
    private var profiles: [String: InputProfile] = [:]
    /// Profiles switched with the View button, which last until the app is opened again from the home screen.
    private var overrides: [String: InputProfile] = [:]
    private var externalPID: pid_t?
    private var activity: NSObjectProtocol?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private var screenFrame: NSRect {
        NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // App Nap would slow the controller polling while another app is in front.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Reading the game controller")
        buildMenu()

        launcher.screenSize = screenFrame.size
        launcher.onActivate = { [weak self] entry in self?.launch(entry) }
        reloadConfig(force: true)

        launcherWindow = FullScreenWindow(frame: screenFrame)
        launcherWindow.contentView = NSHostingView(rootView: LauncherView(model: launcher))

        gamepad = GamepadMonitor()
        gamepad.onConnect = { [weak self] name in
            self?.launcher.controllerName = name
            self?.toast.show("\(name) connected", symbol: "gamecontroller.fill")
        }
        gamepad.onDisconnect = { [weak self] in
            self?.launcher.controllerName = self?.gamepad.connectedName
        }
        launcher.controllerName = gamepad.connectedName
        router = InputRouter(gamepad: gamepad, synth: synth, app: self)
        router.start()

        installEventMonitors()
        observeSystem()
        showLauncher()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyPresentation()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - What's on screen

    func inputContext() -> InputContext {
        if NSApp.isActive {
            if let player = player {
                return .player(overrides[AppController.playerKey] ?? player.entry.input)
            }
            if launcherWindow.isVisible {
                return .launcher
            }
        }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        return .external(app, overrides[app] ?? profiles[app] ?? .pointer)
    }

    func goHome() {
        if mode == .launcher && player == nil && NSApp.isActive && launcherWindow.isVisible { return }
        showLauncher()
    }

    func showLauncher() {
        closePlayer()
        mode = .launcher
        reloadConfig(force: false)
        launcherWindow.setFrame(screenFrame, display: true)
        launcherWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        applyPresentation()
    }

    func toggleProfile() {
        let key: String
        let current: InputProfile
        switch inputContext() {
        case .launcher:
            return
        case .player(let profile):
            key = AppController.playerKey
            current = profile
        case .external(let app, let profile):
            key = app
            current = profile
        }
        let next: InputProfile = current == .pointer ? .keys : .pointer
        overrides[key] = next
        if next == .pointer {
            toast.show("Pointer mode: left stick moves the pointer, A clicks", symbol: "cursorarrow")
        } else {
            toast.show("Arrow-key mode: D-pad and left stick send arrow keys", symbol: "arrow.up.and.down.and.arrow.left.and.right")
        }
    }

    private func launch(_ entry: LauncherEntry) {
        if let problem = entry.problem {
            toast.show(problem, symbol: "exclamationmark.triangle.fill", duration: 5)
            return
        }
        switch entry.kind {
        case .web:
            openPlayer(entry)
        case .browser, .app:
            openExternal(entry)
        case .desktop:
            showDesktop()
        }
    }

    private func openPlayer(_ entry: LauncherEntry) {
        guard let url = entry.url else { return }
        closePlayer()
        overrides[AppController.playerKey] = nil
        let player = WebPlayer(entry: entry, url: url, frame: screenFrame)
        player.onClose = { [weak self] in self?.goHome() }
        self.player = player
        mode = .player
        player.show()
        NSApp.activate(ignoringOtherApps: true)
        toast.show("B goes back. Home, or View and Menu together, returns to MacHome.", symbol: "house.fill")
    }

    private func closePlayer() {
        player?.close()
        player = nil
    }

    private func openExternal(_ entry: LauncherEntry) {
        guard let appURL = entry.appURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.arguments = entry.arguments
        let completion: (NSRunningApplication?, Error?) -> Void = { [weak self] app, error in
            DispatchQueue.main.async { self?.didOpenExternal(entry, app: app, error: error) }
        }
        if entry.kind == .browser, let url = entry.url {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration, completionHandler: completion)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration, completionHandler: completion)
        }
    }

    private func didOpenExternal(_ entry: LauncherEntry, app: NSRunningApplication?, error: Error?) {
        if let error = error {
            toast.show("Couldn't open \(entry.title): \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", duration: 5)
            return
        }
        guard let app = app else { return }
        if let bundleID = app.bundleIdentifier {
            profiles[bundleID] = entry.input
            overrides[bundleID] = nil
        }
        externalPID = app.processIdentifier
        mode = .external
        switch entry.input {
        case .pointer:
            toast.show("Left stick moves the pointer, A clicks. Home returns to MacHome.", symbol: "cursorarrow")
        case .keys, .native:
            toast.show("Home, or View and Menu together, returns to MacHome.", symbol: "house.fill")
        }
    }

    private func showDesktop() {
        closePlayer()
        mode = .desktop
        NSApp.presentationOptions = []
        launcherWindow.orderOut(nil)
        _ = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?
            .activate(options: .activateIgnoringOtherApps)
        toast.show("Desktop. Press Home, or View and Menu together, to return.", symbol: "desktopcomputer", duration: 4)
    }

    /// Hides the Dock and menu bar while MacHome is in front. macOS restores them when another app is.
    private func applyPresentation() {
        guard NSApp.isActive else { return }
        NSApp.presentationOptions = mode == .desktop ? [] : [.hideDock, .hideMenuBar]
    }

    // MARK: - apps.json

    private func reloadConfig(force: Bool) {
        guard force || store.hasChanges else { return }
        do {
            let configs = try store.load()
            launcher.setEntries(configs.map { LauncherEntry(config: $0, baseDirectory: store.directory) })
            launcher.notice = nil
        } catch {
            let message = "apps.json: " + ConfigStore.describe(error)
            launcher.notice = message
            toast.show(message, symbol: "exclamationmark.triangle.fill", duration: 6)
            if launcher.entries.isEmpty {
                launcher.setEntries(ConfigStore.defaultEntries.map { LauncherEntry(config: $0, baseDirectory: store.directory) })
            }
        }
    }

    @objc private func editConfig(_ sender: Any?) {
        do {
            try store.ensureFile()
        } catch {
            toast.show("Couldn't create apps.json: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            return
        }
        if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([store.fileURL], withApplicationAt: textEdit,
                                    configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            _ = NSWorkspace.shared.open(store.fileURL)
        }
    }

    @objc private func reloadConfigAction(_ sender: Any?) {
        reloadConfig(force: true)
    }

    @objc private func showDesktopAction(_ sender: Any?) {
        showDesktop()
    }

    @objc private func goHomeAction(_ sender: Any?) {
        goHome()
    }

    // MARK: - Setup

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "MacHome")
        appMenu.addItem(withTitle: "About MacHome", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        addItem(to: appMenu, "Edit Apps…", #selector(editConfig(_:)), ",")
        addItem(to: appMenu, "Reload Apps", #selector(reloadConfigAction(_:)), "r")
        addItem(to: appMenu, "Home", #selector(goHomeAction(_:)), "w")
        addItem(to: appMenu, "Show Desktop", #selector(showDesktopAction(_:)), "d")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MacHome", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Without an Edit menu, copy and paste don't work in web pages (sign-in forms, for example).
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    /// Arrow keys, Return and Space work on the home screen too, for when a keyboard is handy.
    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.player == nil, self.launcherWindow.isKeyWindow,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 123: self.launcher.move(.left)
            case 124: self.launcher.move(.right)
            case 125: self.launcher.move(.down)
            case 126: self.launcher.move(.up)
            case 36, 49, 76: self.launcher.activateFocused()
            default: break
            }
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.launcher.mouseMovedAt = ProcessInfo.processInfo.systemUptime
            return event
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        // When an app opened from the home screen quits, come back home, as tvOS does.
        observers.append(workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self, self.mode == .external,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == self.externalPID else { return }
            self.showLauncher()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            let frame = self.screenFrame
            self.launcher.screenSize = frame.size
            if self.launcherWindow.isVisible { self.launcherWindow.setFrame(frame, display: true) }
            self.player?.window.setFrame(frame, display: true)
        })
    }
}
