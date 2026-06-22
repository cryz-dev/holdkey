import AppKit
import CoreGraphics
import ApplicationServices

// MARK: - Notification Names

extension Notification.Name {
    static let lockStateChanged   = Notification.Name("com.cryz.holdkey.lockStateChanged")
    static let tapCreationFailed  = Notification.Name("com.cryz.holdkey.tapCreationFailed")
    static let tapStarted         = Notification.Name("com.cryz.holdkey.tapStarted")
}

// MARK: - TriggerKeyConfig

struct TriggerKeyConfig {

    enum Source {
        case modifier(flag: CGEventFlags)   // detected via mouse-event flags (Accessibility only)
        case regular(keyCode: CGKeyCode)    // detected via keyDown/keyUp (needs Input Monitoring)
    }

    let source:      Source
    let displayName: String

    var isModifier: Bool { if case .modifier = source { return true }; return false }

    // Presets
    static let option   = TriggerKeyConfig(source: .modifier(flag: .maskAlternate),  displayName: "Option (⌥)")
    static let control  = TriggerKeyConfig(source: .modifier(flag: .maskControl),    displayName: "Control (⌃)")
    static let shift    = TriggerKeyConfig(source: .modifier(flag: .maskShift),      displayName: "Shift (⇧)")
    static let command  = TriggerKeyConfig(source: .modifier(flag: .maskCommand),    displayName: "Command (⌘)")
    static let capsLock = TriggerKeyConfig(source: .modifier(flag: .maskAlphaShift), displayName: "Caps Lock (⇪)")

    func matchesKeyCode(_ code: CGKeyCode) -> Bool {
        if case .regular(let k) = source { return k == code }
        return false
    }

    // Persistence
    func save() {
        let d = UserDefaults.standard
        d.set(displayName, forKey: "triggerKeyDisplayName")
        switch source {
        case .modifier(let f):
            d.set("modifier", forKey: "triggerKeyType")
            d.set(f.rawValue, forKey: "triggerKeyFlagRaw")
        case .regular(let k):
            d.set("regular",  forKey: "triggerKeyType")
            d.set(Int(k),     forKey: "triggerKeyCode")
        }
    }

    static func load() -> TriggerKeyConfig {
        let d    = UserDefaults.standard
        let type = d.string(forKey: "triggerKeyType") ?? "modifier"
        let name = d.string(forKey: "triggerKeyDisplayName") ?? TriggerKeyConfig.option.displayName
        if type == "regular" {
            let code = CGKeyCode(d.integer(forKey: "triggerKeyCode"))
            return TriggerKeyConfig(source: .regular(keyCode: code), displayName: name)
        } else {
            let raw = d.object(forKey: "triggerKeyFlagRaw") as? UInt64 ?? CGEventFlags.maskAlternate.rawValue
            return TriggerKeyConfig(source: .modifier(flag: CGEventFlags(rawValue: raw)), displayName: name)
        }
    }
}

// MARK: - MouseLockManager

final class MouseLockManager {

    // Settings
    var isEnabled: Bool = true { didSet { saveSettings() } }
    var onlyInPremierePro: Bool = true { didSet { saveSettings() } }
    var triggerKey: TriggerKeyConfig = .option {
        didSet {
            if isLockActive { deactivateLock() }
            isKeyHeld = false
            saveSettings()
            // Recreate tap: mask depends on whether we need keyboard events
            if eventTap != nil { restartTap() }
        }
    }

    // State (main-thread only)
    private(set) var isLockActive = false
    private var lockedY:   CGFloat = 0
    private var lockedX:   CGFloat = 0   // last X (for the release-time warp)
    private var isKeyHeld: Bool    = false
    private var isDragging: Bool    = false   // left mouse button currently held
    private var isPremiereActive   = false

    // EventTap
    var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Static C Callback
    static let eventCallback: CGEventTapCallBack = { proxy, eventType, event, userInfoPtr in
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let ptr = userInfoPtr {
                let mgr = Unmanaged<MouseLockManager>.fromOpaque(ptr).takeUnretainedValue()
                if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let ptr = userInfoPtr else { return Unmanaged.passUnretained(event) }
        let mgr = Unmanaged<MouseLockManager>.fromOpaque(ptr).takeUnretainedValue()
        return mgr.handle(eventType: eventType, event: event)
    }

    // MARK: - Event Mask
    private func currentEventMask() -> CGEventMask {
        var mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
          | (1 << CGEventType.leftMouseDragged.rawValue)
          | (1 << CGEventType.rightMouseDragged.rawValue)
          | (1 << CGEventType.leftMouseDown.rawValue)    // track drag start
          | (1 << CGEventType.leftMouseUp.rawValue)      // commit on the locked line
        if triggerKey.isModifier {
            // flagsChanged fires the INSTANT the modifier is pressed (and carries the
            // cursor location), so we can capture lockedY with zero lag instead of
            // waiting for the next mouse event (which is what caused the ~few-px offset).
            mask |= (1 << CGEventType.flagsChanged.rawValue)
        } else {
            mask |= (1 << CGEventType.keyDown.rawValue)
                  | (1 << CGEventType.keyUp.rawValue)
        }
        return mask
    }

    // MARK: - Start / Stop
    func startTap() {
        guard eventTap == nil else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: currentEventMask(),
            callback: MouseLockManager.eventCallback,
            userInfo: selfPtr
        ) else {
            // tapCreate returns nil when Accessibility permission is missing.
            NotificationCenter.default.post(name: .tapCreationFailed, object: nil)
            return
        }

        self.eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NotificationCenter.default.post(name: .tapStarted, object: nil)
    }

    func stopTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        deactivateLock()
        isKeyHeld = false
    }

    private func restartTap() {
        stopTap()
        startTap()
    }

    // MARK: - Event Router
    func handle(eventType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        if onlyInPremierePro && !isPremiereActive {
            if isLockActive { deactivateLock() }
            return Unmanaged.passUnretained(event)
        }

        switch eventType {
        case .flagsChanged where triggerKey.isModifier:
            handleFlagsChanged(event: event)

        case .keyDown where !triggerKey.isModifier:
            handleKeyDown(event: event)
        case .keyUp where !triggerKey.isModifier:
            handleKeyUp(event: event)

        case .leftMouseDown:
            handleMouseDown(event: event)
        case .leftMouseUp:
            handleMouseUp(event: event)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            handleMouse(event: event)

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Modifier handler (precise, zero-lag activation)
    private func handleFlagsChanged(event: CGEvent) {
        guard case .modifier(let flag) = triggerKey.source else { return }
        let present = event.flags.contains(flag)
        if present && !isLockActive {
            activateLock(at: event.location)          // lockedY at the exact press instant
        } else if !present && isLockActive {
            if isDragging {
                // Latch: a drag is in progress. Keep Y masked on every drag event
                // until the mouse button is released (handleMouseUp), so the curve
                // can't drop in the gap between releasing the key and the button.
            } else {
                warpToLockedLine(x: event.location.x) // precise release, no lag
                deactivateLock()
            }
        }
    }

    // MARK: - Mouse handler (fallback modifier detection + Y redirect)
    private func handleMouse(event: CGEvent) {
        if case .modifier(let flag) = triggerKey.source {
            // Read modifier state directly off the mouse event — no keyboard tap needed.
            let present = event.flags.contains(flag)
            if present && !isLockActive {
                activateLock(at: event.location)
            } else if !present && isLockActive && !isDragging {
                // Fallback release (no flagsChanged seen) — only when NOT mid-drag.
                // During a drag the lock is latched until the mouse button comes up.
                let x = event.location.x
                event.location = CGPoint(x: x, y: lockedY)
                warpToLockedLine(x: x)
                deactivateLock()
            }
        } else {
            // Regular-key trigger: isKeyHeld is driven by keyDown/keyUp.
            if isKeyHeld && !isLockActive {
                activateLock(at: event.location)
            }
        }

        if isLockActive {
            redirectY(event: event)
        }
    }

    // MARK: - Mouse button (drag latch)
    private func handleMouseDown(event: CGEvent) {
        isDragging = true
        // If already locked when the grab starts, anchor the lock line to the grab
        // point — handles "hold key, then click the handle" as well as the reverse.
        if isLockActive {
            lockedY = event.location.y
            lockedX = event.location.x
        }
    }

    private func handleMouseUp(event: CGEvent) {
        isDragging = false
        guard isLockActive else { return }
        // Commit the release point ON the locked line so the keyframe never drops,
        // even if the key was let go earlier in the drag.
        let x = event.location.x
        event.location = CGPoint(x: x, y: lockedY)
        // End the lock unless the user is still physically holding the trigger.
        if !modifierStillHeld(event) {
            warpToLockedLine(x: x)
            deactivateLock()
        }
    }

    private func modifierStillHeld(_ event: CGEvent) -> Bool {
        if case .modifier(let flag) = triggerKey.source { return event.flags.contains(flag) }
        return isKeyHeld
    }

    // MARK: - Regular key handlers
    private func handleKeyDown(event: CGEvent) {
        guard case .regular(let keyCode) = triggerKey.source else { return }
        let eventKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKey == keyCode, !isKeyHeld else { return }
        isKeyHeld = true
    }

    private func handleKeyUp(event: CGEvent) {
        guard case .regular = triggerKey.source else { return }
        let eventKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard triggerKey.matchesKeyCode(eventKey) else { return }
        isKeyHeld = false
        if isLockActive && !isDragging {
            warpToLockedLine(x: lockedX)   // no mouse event here → use last known X
            deactivateLock()
        }
        // If mid-drag, latch until mouseUp (handleMouseUp finishes the release).
    }

    // MARK: - Lock / Unlock
    private func activateLock(at location: CGPoint) {
        guard !isLockActive else { return }
        lockedY      = location.y
        lockedX      = location.x   // start X = where the lock began
        isLockActive = true
        NotificationCenter.default.post(name: .lockStateChanged, object: true)
    }

    private func deactivateLock() {
        guard isLockActive else { return }
        isLockActive = false
        NotificationCenter.default.post(name: .lockStateChanged, object: false)
    }

    // MARK: - Y Redirect
    // Pin BOTH the in-flight event AND the authoritative OS cursor to lockedY.
    // Only modifying the event leaves the WindowServer's real cursor drifting with
    // the hardware → it snaps back on release. Warping keeps the real cursor on the
    // locked line (same technique as Windows/AHK mouse-axis locking scripts).
    // CGEvent.location and CGWarpMouseCursorPosition share the same global display
    // space (origin top-left, Y down) → values are directly compatible.
    private func redirectY(event: CGEvent) {
        // Keep the system's natural, correctly-accelerated X — do NOT warp during
        // the hold. (Warping decouples hardware→cursor and rescales movement, which
        // made X feel oversensitive.) We only mask Y in the event the app receives.
        // The real cursor's Y is re-pinned once, on release, to avoid the snap.
        let x = event.location.x
        lockedX = x   // remember last X for the release-time warp
        event.location = CGPoint(x: x, y: lockedY)
        event.setIntegerValueField(.mouseEventDeltaY, value: 0)
    }

    // Re-pin the real cursor onto the locked line exactly once, at release, so
    // movement after the key is let go continues from there (no downward snap).
    private func warpToLockedLine(x: CGFloat) {
        CGWarpMouseCursorPosition(CGPoint(x: x, y: lockedY))
        CGAssociateMouseAndMouseCursorPosition(1)   // re-enable HW tracking immediately
    }

    // MARK: - Premiere Pro Detection
    // Adobe appends the version to the bundle id, e.g. "com.adobe.PremierePro.26"
    // (Premiere 2026), ".25", ".24"… So we match by prefix, not exact string —
    // a hardcoded "com.adobe.premierepro" never matched any real version.
    private func isPremiere(_ bundleID: String?) -> Bool {
        (bundleID ?? "").lowercased().hasPrefix("com.adobe.premierepro")
    }

    func startWorkspaceObservation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        isPremiereActive = isPremiere(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    @objc private func activeAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        isPremiereActive = isPremiere(app?.bundleIdentifier)
        if !isPremiereActive {
            isKeyHeld = false
            if isLockActive { deactivateLock() }
        }
    }

    // MARK: - Persistence
    func loadSettings() {
        let d = UserDefaults.standard
        isEnabled         = d.object(forKey: "isEnabled")         as? Bool ?? true
        onlyInPremierePro = d.object(forKey: "onlyInPremierePro") as? Bool ?? true
        triggerKey        = TriggerKeyConfig.load()
    }

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(isEnabled,         forKey: "isEnabled")
        d.set(onlyInPremierePro, forKey: "onlyInPremierePro")
        triggerKey.save()
    }
}
