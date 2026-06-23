import AppKit
import ApplicationServices
import Darwin
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let manager = MouseLockManager()
    private var recorderWindow: KeyRecorderWindow?
    private var permissionTimer: Timer?

    private var tapIsRunning = false
    private var justGranted  = false   // show "✅ Granted" transition briefly

    // MARK: - App Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        enforceSingleInstance()
        NSApp.setActivationPolicy(.accessory)
        manager.loadSettings()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self            // menuNeedsUpdate refreshes state on every open
        statusItem.menu = menu

        // Observers BEFORE startTap() so .tapStarted is caught synchronously
        manager.startWorkspaceObservation()
        NotificationCenter.default.addObserver(self, selector: #selector(lockStateChanged(_:)),
                                               name: .lockStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tapDidStart),
                                               name: .tapStarted, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tapCreationFailed),
                                               name: .tapCreationFailed, object: nil)

        // If permission is already granted, this starts the tap immediately.
        manager.startTap()
        updateStatusIcon(locked: false)
    }

    private func enforceSingleInstance() {
        let currentPID = getpid()
        let currentBundleID = Bundle.main.bundleIdentifier
        let duplicates = NSWorkspace.shared.runningApplications.filter { app in
            app.processIdentifier != currentPID && app.bundleIdentifier == currentBundleID
        }

        for app in duplicates {
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }
    }

    // MARK: - Status Icon
    // Icon is always `cursorarrow`. Tint:
    //   green  → enabled & running (ready)
    //   yellow → horizontal lock ACTIVE
    //   grey   → running but disabled
    //   red    → accessibility permission missing

    private func updateStatusIcon(locked: Bool) {
        guard let button = statusItem.button else { return }

        // Choose colour by state
        let color: NSColor
        let tip: String
        if locked {
            color = .systemYellow
            tip   = "HoldKey — Horizontal lock ACTIVE"
        } else if tapIsRunning {
            if manager.isEnabled {
                color = .systemGreen             // green whenever enabled & ready
                tip   = "HoldKey — Enabled · Hold \(manager.triggerKey.displayName) to lock"
            } else {
                color = .secondaryLabelColor     // dimmed when disabled
                tip   = "HoldKey — Disabled"
            }
        } else {
            color = .systemRed
            tip   = "HoldKey — Accessibility permission required"
        }

        // NON-template image + palette colour forces the exact colour.
        // (A template image would be auto-recoloured by the menu bar and
        //  would ignore contentTintColor → the white never showed.)
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let img = NSImage(systemSymbolName: "cursorarrow",
                             accessibilityDescription: "HoldKey")?
            .withSymbolConfiguration(cfg) {
            img.isTemplate = false
            button.image   = img
        }
        button.contentTintColor = nil
        button.toolTip = tip
    }

    // MARK: - NSMenuDelegate
    // Repopulate the menu every time it's about to open → always reflects truth.

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Self-heal: retry the tap directly (tapCreate is NOT cached, unlike
        // AXIsProcessTrusted) — so a freshly granted permission is picked up here.
        if !tapIsRunning {
            manager.startTap()
        }
        populateMenu(menu)
    }

    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        // Header
        let header = NSMenuItem(title: "HoldKey", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Status dot
        menu.addItem(makeStatusLineItem())
        menu.addItem(.separator())

        // Enabled toggle
        let enabledItem = NSMenuItem(title: "Enabled",
                                     action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state  = manager.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        // Only in Premiere Pro toggle
        let premiereItem = NSMenuItem(title: "Only in Premiere Pro",
                                      action: #selector(togglePremiereOnly), keyEquivalent: "")
        premiereItem.target = self
        premiereItem.state  = manager.onlyInPremierePro ? .on : .off
        menu.addItem(premiereItem)

        // Start at Login (macOS 13+)
        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(title: "Start at Login",
                                       action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            loginItem.state  = launchAtLoginEnabled ? .on : .off
            menu.addItem(loginItem)
        }

        menu.addItem(.separator())

        // Trigger key display + change button
        let keyLabel = NSMenuItem(title: "Hold Key:  \(manager.triggerKey.displayName)",
                                  action: nil, keyEquivalent: "")
        keyLabel.isEnabled = false
        menu.addItem(keyLabel)

        let changeItem = NSMenuItem(title: "    Change Key…",
                                    action: #selector(openKeyRecorder), keyEquivalent: "")
        changeItem.target = self
        menu.addItem(changeItem)

        menu.addItem(.separator())

        // Accessibility row
        if !AXIsProcessTrusted() {
            let permItem = NSMenuItem(title: "⚠️  Grant Accessibility Permission…",
                                      action: #selector(grantPermission), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
            menu.addItem(.separator())
        } else if justGranted {
            // Brief confirmation right after granting
            let done = NSMenuItem()
            done.isEnabled = false
            let str = NSMutableAttributedString()
            str.append(NSAttributedString(string: "✅ ",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            str.append(NSAttributedString(string: "Permission granted",
                attributes: [.foregroundColor: NSColor.systemGreen,
                             .font: NSFont.systemFont(ofSize: 13)]))
            done.attributedTitle = str
            menu.addItem(done)
            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "Quit HoldKey",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func makeStatusLineItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let (dot, text, dotColor): (String, String, NSColor) = tapIsRunning
            ? ("●", " Running — ready", .systemGreen)
            : ("⊘", " Needs Accessibility permission", .systemOrange)

        let str = NSMutableAttributedString()
        str.append(NSAttributedString(string: dot,
            attributes: [.foregroundColor: dotColor,
                         .font: NSFont.systemFont(ofSize: 11, weight: .semibold)]))
        str.append(NSAttributedString(string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: 11)]))
        item.attributedTitle = str
        return item
    }

    // MARK: - Toggle Actions

    @objc private func toggleEnabled() {
        manager.isEnabled = !manager.isEnabled
        updateStatusIcon(locked: false)   // reflect green/grey immediately
    }

    @objc private func togglePremiereOnly() {
        manager.onlyInPremierePro = !manager.onlyInPremierePro
    }

    // MARK: - Launch at Login (SMAppService, macOS 13+)

    private var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("HoldKey: launch-at-login toggle failed: \(error)")
        }
    }

    // MARK: - Key Recorder

    @objc private func openKeyRecorder() {
        if let existing = recorderWindow, existing.isVisible { return }
        let window = KeyRecorderWindow()
        recorderWindow = window
        window.startRecording { [weak self] config in
            guard let self else { return }
            self.manager.triggerKey = config
            self.updateStatusIcon(locked: false)
        }
    }

    // MARK: - Accessibility

    @objc private func grantPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        startPermissionPolling()
    }

    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if self.tapIsRunning { timer.invalidate(); self.permissionTimer = nil; return }
            // Attempt the tap directly. tapCreate reflects a freshly granted
            // permission immediately (AXIsProcessTrusted would stay cached=false
            // for this process until relaunch). startTap() sets tapIsRunning
            // synchronously via the .tapStarted notification on success.
            self.manager.startTap()
            if self.tapIsRunning {
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
        // .common modes → fires even while the menu is open, so the user
        // sees the live "needs permission → granted" transition.
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - Notification Handlers

    @objc private func lockStateChanged(_ note: Notification) {
        updateStatusIcon(locked: (note.object as? Bool) ?? false)
    }

    @objc private func tapDidStart() {
        let wasRunning = tapIsRunning
        tapIsRunning = true
        updateStatusIcon(locked: false)

        // First time the tap comes up after a grant → show the brief confirmation.
        if !wasRunning {
            justGranted = true
            populateMenu(menu)   // refresh in case the menu is currently open
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.justGranted = false
                if let m = self?.menu { self?.populateMenu(m) }
            }
        }
    }

    @objc private func tapCreationFailed() {
        tapIsRunning = false
        updateStatusIcon(locked: false)
        // AXIsProcessTrusted true but tap still failed → likely Input Monitoring.
        if AXIsProcessTrusted() {
            NSLog("HoldKey: tap creation failed despite Accessibility trust — check Input Monitoring.")
        }
        startPermissionPolling()
    }
}
