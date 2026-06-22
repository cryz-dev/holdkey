import AppKit
import CoreGraphics

// MARK: - KeyRecorderWindow
// A small floating panel that captures the next key or modifier press
// and returns it as a TriggerKeyConfig.

final class KeyRecorderWindow: NSPanel {

    var onKeyRecorded: ((TriggerKeyConfig) -> Void)?
    private var localMonitor: Any?

    // MARK: - Init

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title         = "HoldKey — Set Trigger Key"
        level         = .floating
        isReleasedWhenClosed = false
        setupUI()
    }

    private func setupUI() {
        let mainLabel = NSTextField(labelWithString: "Press any key to set it as the\nhorizontal lock trigger")
        mainLabel.alignment  = .center
        mainLabel.font       = .systemFont(ofSize: 14, weight: .medium)
        mainLabel.isEditable = false

        let hintLabel = NSTextField(labelWithString: "Supports: letters, numbers, F1–F15, modifier keys, arrow keys…\nPress Escape to cancel.")
        hintLabel.alignment = .center
        hintLabel.font      = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.isEditable = false

        let stack = NSStackView(views: [mainLabel, hintLabel])
        stack.orientation = .vertical
        stack.spacing     = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView!.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView!.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Start Recording

    func startRecording(callback: @escaping (TriggerKeyConfig) -> Void) {
        onKeyRecorded = callback
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Track which modifiers are currently pressed to detect press (not release)
        var lastModifiers: NSEvent.ModifierFlags = []

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }

            switch event.type {

            // --- Regular key pressed ---
            case .keyDown:
                let keyCode = event.keyCode
                if keyCode == 53 { // Escape = cancel
                    self.cancelRecording()
                    return nil
                }
                let name   = KeyRecorderWindow.nameFor(keyCode: keyCode, event: event)
                let config = TriggerKeyConfig(source: .regular(keyCode: CGKeyCode(keyCode)),
                                              displayName: name)
                self.finish(config: config)
                return nil

            // --- Modifier key pressed ---
            case .flagsChanged:
                let current = event.modifierFlags.intersection([.option, .control, .shift, .capsLock, .command, .function])
                // Only react when a new modifier appears (press, not release)
                let pressed = current.subtracting(lastModifiers)
                lastModifiers = current
                guard !pressed.isEmpty else { return nil }

                let config: TriggerKeyConfig?
                if pressed.contains(.option) {
                    config = .option
                } else if pressed.contains(.control) {
                    config = .control
                } else if pressed.contains(.shift) {
                    config = .shift
                } else if pressed.contains(.capsLock) {
                    config = .capsLock
                } else if pressed.contains(.command) {
                    config = TriggerKeyConfig(source: .modifier(flag: .maskCommand), displayName: "Command (⌘)")
                } else {
                    // Fn or unknown modifier — not reliably capturable, ignore
                    config = nil
                }

                if let cfg = config {
                    self.finish(config: cfg)
                }
                return nil

            default:
                return event
            }
        }
    }

    // MARK: - Finish / Cancel

    private func finish(config: TriggerKeyConfig) {
        stopMonitor()
        onKeyRecorded?(config)
        close()
    }

    private func cancelRecording() {
        stopMonitor()
        close()
    }

    private func stopMonitor() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    override func close() {
        stopMonitor()  // safety: always clean up on close (including red X click)
        super.close()
    }

    // MARK: - Key Name Lookup

    static func nameFor(keyCode: UInt16, event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "Return (↩)",
            48: "Tab (⇥)",
            49: "Space (␣)",
            51: "Delete (⌫)",
            71: "Clear",
            76: "Enter (⌤)",
            96: "F5",  97: "F6",  98: "F7",  99: "F3",
           100: "F8",  101: "F9", 103: "F11", 105: "F13",
           107: "F14", 109: "F10", 111: "F12", 113: "F15",
           114: "Help", 115: "Home (↖)", 116: "Page Up (⇞)",
           117: "Forward Delete (⌦)", 119: "End (↘)",
           121: "Page Down (⇟)",
           118: "F4",  120: "F2", 122: "F1",
           123: "← Arrow", 124: "→ Arrow", 125: "↓ Arrow", 126: "↑ Arrow",
        ]
        if let name = special[keyCode] { return name }

        // Use the character the key produces (ignore modifier state)
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let upper = chars.uppercased()
            // Skip control characters
            if let first = upper.unicodeScalars.first, first.value >= 32 {
                return upper
            }
        }
        return "Key \(keyCode)"
    }
}
