import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties
    var mainWindow: NSWindow!
    var webViewController: MainWindowController!
    var settingsWindowController: SettingsWindowController!
    var statusBarController: StatusBarController?
    var backendManager: BackendManager!
    var hotkeyManager: HotkeyManager!
    var loadingViewController: LoadingViewController?
    var missingFilesViewController: MissingFilesViewController?
    var authRequiredViewController: AuthRequiredViewController?
    private var aboutWindow: NSWindow?

    // Internal shortcut state (default Cmd+S: keyCode 1, modifiers 256)
    var internalSidebarKeyCode: UInt32 = 1
    var internalSidebarModifiers: UInt32 = 256

    // Tracks the page the user actually wants when the app is cold-launched.
    // If an AppleScript "show page X" arrives before the backend is ready,
    // we stash it here and the auth-ready handler will load X instead of the
    // default. Set to nil once the initial page has loaded.
    private var pendingInitialPage: DashboardPage?
    private var hasLoadedInitialPage = false

    private var isMenuBarMode: Bool {
        get { UserDefaults.standard.bool(forKey: "menuBarMode") }
        set { UserDefaults.standard.set(newValue, forKey: "menuBarMode") }
    }

    private var isFloatOnTop: Bool {
        get {
            // Default to false if never set
            if UserDefaults.standard.object(forKey: "floatOnTop") == nil { return false }
            return UserDefaults.standard.bool(forKey: "floatOnTop")
        }
        set { UserDefaults.standard.set(newValue, forKey: "floatOnTop") }
    }

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        backendManager = BackendManager()

        // Create and show the main window first so any preflight error is
        // shown inside the app rather than as an external dialog.
        createMainWindow()
        showWindowOnCurrentScreen()
        buildMenu()

        // Preflight: if required files are missing, show an in-window error
        // and stop here — the Flask backend would otherwise hang silently.
        let missing = backendManager.checkRequiredFiles()
        if !missing.isEmpty, let contentView = mainWindow.contentView {
            missingFilesViewController = MissingFilesViewController(
                parentView: contentView,
                missing: missing,
                projectRoot: backendManager.projectRoot
            )
            return
        }

        backendManager.start()

        if let contentView = mainWindow.contentView {
            loadingViewController = LoadingViewController(parentView: contentView)
        }

        // Create the web view controller (adds WebView behind the loading screen)
        webViewController = MainWindowController(window: mainWindow)

        // Set up hotkey manager
        hotkeyManager = HotkeyManager()
        hotkeyManager.delegate = self
        hotkeyManager.loadAndRegisterAll()

        // Set up settings window controller
        settingsWindowController = SettingsWindowController(hotkeyManager: hotkeyManager, webView: webViewController.webView)
        settingsWindowController.delegate = self

        // Apply Dock/Menu Bar mode
        applyAppMode()

        // Wait for backend to be ready with progress reporting
        backendManager.waitForReady(progress: { [weak self] progress in
            DispatchQueue.main.async {
                self?.loadingViewController?.setProgress(CGFloat(progress))
            }
        }) { [weak self] in
            DispatchQueue.main.async {
                self?.checkAuthAndProceed()
            }
        }

        loadInternalSidebarShortcut()

        // Intercept internal shortcuts cleanly
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let carbonMods = HotkeyManager.cocoaToCarbonModifiers(event.modifierFlags.intersection([.command, .option, .control, .shift]))
            
            if UInt32(event.keyCode) == self.internalSidebarKeyCode && carbonMods == self.internalSidebarModifiers {
                self.webViewController.webView.evaluateJavaScript("toggleSidebar()", completionHandler: nil)
                return nil // Swallow event
            }
            return event
        }
    }

    func loadInternalSidebarShortcut() {
        if let dict = UserDefaults.standard.dictionary(forKey: "internalSidebarShortcut") {
            if let kc = dict["keyCode"] as? NSNumber { self.internalSidebarKeyCode = kc.uint32Value }
            if let mods = dict["modifiers"] as? NSNumber { self.internalSidebarModifiers = mods.uint32Value }
        } else {
            // Default ⌘S
            self.internalSidebarKeyCode = 1
            self.internalSidebarModifiers = 256
        }
    }

    // MARK: - Auth gating

    /// Check whether the Flask backend reports a valid Spotify token.
    /// If yes → load dashboard. If no → show in-app auth panel.
    private func checkAuthAndProceed() {
        guard let url = URL(string: "http://127.0.0.1:8888/api/auth-status") else {
            self.loadDashboardAfterAuth()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }

            var authenticated = false
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = json["authenticated"] as? Bool {
                authenticated = value
            }

            DispatchQueue.main.async {
                if authenticated {
                    self.loadDashboardAfterAuth()
                } else {
                    self.showAuthPanel()
                }
            }
        }.resume()
    }

    private func showAuthPanel() {
        // Dismiss loading screen first
        loadingViewController?.dismiss { [weak self] in
            self?.loadingViewController = nil
        }

        guard let contentView = mainWindow.contentView else { return }
        authRequiredViewController = AuthRequiredViewController(parentView: contentView) { [weak self] in
            self?.authRequiredViewController = nil
            self?.loadDashboardAfterAuth()
        }
    }

    private func loadDashboardAfterAuth() {
        let initialPage = pendingInitialPage ?? .playlists
        pendingInitialPage = nil
        hasLoadedInitialPage = true
        webViewController.loadPage(initialPage)

        // Poll WebView until the DOM actually contains the rendered playlists
        func checkWebViewReady(attemptsLeft: Int) {
            guard attemptsLeft > 0 else {
                self.loadingViewController?.dismiss { [weak self] in
                    self?.loadingViewController = nil
                }
                return
            }

            let js = "document.getElementById('playlist-grid') ? document.getElementById('playlist-grid').children.length : -1"
            self.webViewController.webView.evaluateJavaScript(js) { [weak self] (result, _) in
                if let count = result as? Int, count > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self?.loadingViewController?.dismiss {
                            self?.loadingViewController = nil
                        }
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        checkWebViewReady(attemptsLeft: attemptsLeft - 1)
                    }
                }
            }
        }
        checkWebViewReady(attemptsLeft: 50)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregisterAll()
        backendManager?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showWindowOnCurrentScreen()
        }
        return true
    }

    // MARK: - Window Creation

    private func createMainWindow() {
        // Fill the entire visible screen area on launch
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]

        mainWindow = NSWindow(
            contentRect: screenFrame,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        mainWindow.title = "Spotify Dashboard"
        mainWindow.level = isFloatOnTop ? .floating : .normal
        mainWindow.isReleasedWhenClosed = false
        mainWindow.delegate = self
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.titleVisibility = .hidden
        mainWindow.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1.0)

        // Allow fullscreen via the green traffic-light button
        mainWindow.collectionBehavior = [.fullScreenPrimary]

        // Minimum reasonable size, no maximum cap
        mainWindow.minSize = NSSize(width: 800, height: 500)

    }

    // MARK: - Window Show/Hide

    func showWindowOnCurrentScreen() {
        // Fill the entire visible area of the current monitor
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            mainWindow.setFrame(screen.visibleFrame, display: true)
        }

        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        mainWindow.orderOut(nil)
    }

    func toggleWindow() {
        if mainWindow.isVisible {
            hideWindow()
        } else {
            showWindowOnCurrentScreen()
        }
    }

    /// Show the window and navigate to a specific page.
    /// Skips reloading the WebView if the window is already visible on this page —
    /// so re-running an AppleScript / hotkey for the active page is a no-op
    /// (just keeps the window front) instead of a full reload.
    /// If the app is cold-launched and the backend isn't ready yet, the page
    /// is stashed and loaded once auth completes (avoiding a flash to Playlists).
    func showPage(_ page: DashboardPage) {
        if !hasLoadedInitialPage {
            pendingInitialPage = page
            showWindowOnCurrentScreen()
            return
        }
        let alreadyShowing = mainWindow.isVisible && webViewController.currentPage == page
        if !alreadyShowing {
            webViewController.loadPage(page)
        }
        showWindowOnCurrentScreen()
    }

    /// Toggle visibility; if showing, navigate to a specific page
    func togglePage(_ page: DashboardPage) {
        if mainWindow.isVisible {
            // If already on this page, hide. Otherwise navigate.
            if webViewController.currentPage == page {
                hideWindow()
            } else {
                webViewController.loadPage(page)
            }
        } else {
            webViewController.loadPage(page)
            showWindowOnCurrentScreen()
        }
    }

    // MARK: - App Mode (Dock vs Menu Bar)

    func applyAppMode() {
        if isMenuBarMode {
            NSApp.setActivationPolicy(.accessory)
            if statusBarController == nil {
                statusBarController = StatusBarController()
                statusBarController?.delegate = self
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            statusBarController?.remove()
            statusBarController = nil
        }
    }

    func setFloatOnTop(_ enabled: Bool) {
        isFloatOnTop = enabled
        mainWindow.level = enabled ? .floating : .normal
    }

    func setMenuBarMode(_ enabled: Bool) {
        isMenuBarMode = enabled
        applyAppMode()
        if enabled {
            // When switching to menu bar mode, make sure window stays accessible
            showWindowOnCurrentScreen()
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About Spotify Dashboard",
                                   action: #selector(showAboutPanel),
                                   keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Spotify Dashboard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Spotify Dashboard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Playlists", action: #selector(navigateToPlaylists), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Tracker", action: #selector(navigateToTracker), keyEquivalent: "2")
        viewMenu.addItem(withTitle: "Queue", action: #selector(navigateToQueue), keyEquivalent: "3")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reloadPage), keyEquivalent: "r")
        viewMenu.addItem(NSMenuItem.separator())
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "+")
        zoomInItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(zoomInItem)
        // Also allow ⌘= (unshifted plus key)
        let zoomInAlt = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "=")
        zoomInAlt.keyEquivalentModifierMask = [.command]
        zoomInAlt.isAlternate = true
        viewMenu.addItem(zoomInAlt)
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom), keyEquivalent: "0")
        viewMenu.addItem(NSMenuItem.separator())
        let floatItem = NSMenuItem(title: "Float on Top", action: #selector(toggleFloatOnTop(_:)), keyEquivalent: "")
        floatItem.state = isFloatOnTop ? .on : .off
        viewMenu.addItem(floatItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func openSettings() {
        settingsWindowController.showWindow()
    }

    @objc func showAboutPanel() {
        if aboutWindow == nil {
            aboutWindow = buildAboutWindow()
        }
        aboutWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }

    private func buildAboutWindow() -> NSWindow {
        let info = Bundle.main.infoDictionary ?? [:]
        let appName = (info["CFBundleName"] as? String) ?? "Spotify Dashboard"
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? ""
        let displayVersion = (info["SpotifyDashboardVersionDisplay"] as? String)
            ?? (info["CFBundleVersion"] as? String ?? "")

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "About \(appName)"
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 48, left: 48, bottom: 48, right: 48)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 192).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 192).isActive = true
        stack.addArrangedSubview(iconView)

        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.systemFont(ofSize: 32, weight: .bold)
        nameLabel.alignment = .center
        stack.addArrangedSubview(nameLabel)

        let versionLabel = NSTextField(labelWithString: "Version \(shortVersion)")
        versionLabel.font = NSFont.systemFont(ofSize: 22, weight: .medium)
        versionLabel.textColor = .labelColor
        versionLabel.alignment = .center
        stack.addArrangedSubview(versionLabel)

        let buildLabel = NSTextField(labelWithString: displayVersion)
        buildLabel.font = NSFont.monospacedSystemFont(ofSize: 17, weight: .regular)
        buildLabel.textColor = .labelColor
        buildLabel.alignment = .center
        stack.addArrangedSubview(buildLabel)

        guard let content = win.contentView else { return win }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        return win
    }

    @objc func navigateToPlaylists() {
        showPage(.playlists)
    }

    @objc func navigateToTracker() {
        showPage(.tracker)
    }

    @objc func navigateToQueue() {
        showPage(.queue)
    }

    @objc func reloadPage() {
        webViewController.reload()
    }

    @objc func zoomIn() {
        webViewController.zoomIn()
    }

    @objc func zoomOut() {
        webViewController.zoomOut()
    }

    @objc func resetZoom() {
        webViewController.resetZoom()
    }

    @objc func toggleFloatOnTop(_ sender: NSMenuItem) {
        let newState = !isFloatOnTop
        setFloatOnTop(newState)
        sender.state = newState ? .on : .off
        settingsWindowController.updateFloatOnTopState(newState)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of closing so AppleScript can toggle
        hideWindow()
        return false
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate: HotkeyManagerDelegate {
    func hotkeyTriggered(for page: DashboardPage) {
        togglePage(page)
    }
}

// MARK: - SettingsDelegate

extension AppDelegate: SettingsDelegate {
    func settingsDidChangeAppMode(menuBarMode: Bool) {
        setMenuBarMode(menuBarMode)
    }

    func settingsDidChangeFloatOnTop(enabled: Bool) {
        setFloatOnTop(enabled)
        // Update the View menu checkmark
        if let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu,
           let floatItem = viewMenu.item(withTitle: "Float on Top") {
            floatItem.state = enabled ? .on : .off
        }
    }
}

// MARK: - StatusBarDelegate

extension AppDelegate: StatusBarDelegate {
    func statusBarShowPage(_ page: DashboardPage) {
        showPage(page)
    }

    func statusBarOpenSettings() {
        openSettings()
    }

    func statusBarQuit() {
        NSApp.terminate(nil)
    }
}
