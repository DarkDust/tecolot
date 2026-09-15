//
//  ShortcutEditView.swift
//  Tecolot
//
//  Records key presses and updates a key binding with the detected shortcut.
//

import SwiftUI
import AppKit

/// Shows the shortcut of a key binding and allows to edit the shortcut by recording key presses.
struct ShortcutEditView: View {
    
    let keyBinding: TerminalKeyBinding
    let update: (TerminalKeyBinding) -> Void
    
    @State private var state: State = .idle
    @State private var inFlightShortcut: Shortcut?

    var body: some View {
        ZStack(alignment: state == .recording ? .center : .trailing) {
            // Dummy view that establishes a stable but dynamic view size.
            idleView(forMeasurement: true).opacity(0)
            
            switch state {
            case .idle:
                idleView()
                
            case .recording:
                recordingView
            }
        }
        .background(state == .recording ? .green.opacity(0.5) : .clear)
    }
    
}


private extension ShortcutEditView {
    enum State {
        case idle
        case recording
    }
    
    /// Helper struct to record and print keyboard shortcuts.
    struct Shortcut: Equatable {
        var key: String
        var modifiers: TerminalKeyModifiers
        
        init() {
            self.key = ""
            self.modifiers = []
        }
        
        init(from keyBinding: TerminalKeyBinding) {
            self.key = keyBinding.key
            self.modifiers = keyBinding.modifiers
        }
        
        var isEmpty: Bool {
            key.isEmpty && modifiers.isEmpty
        }
        
        var stringRepresentation: String {
            var text = ""
            // The standard macOS shortcut order is:
            // Control → Option → Shift → Command → [key]
            if modifiers.contains(.control) { text.append("⌃") }
            if modifiers.contains(.option) { text.append("⌥") }
            if modifiers.contains(.shift) { text.append("⇧") }
            if modifiers.contains(.command) { text.append("⌘") }
            
            if let character = key.first {
                switch KeyEquivalent(character) {
                case .upArrow: text.append("↑")
                case .downArrow: text.append("↓")
                case .leftArrow: text.append("←")
                case .rightArrow: text.append("→")
                case .escape: text.append("⎋")
                case .delete: text.append("⌫")
                case .deleteForward: text.append("⌦")
                case .home: text.append("↖︎")
                case .end: text.append("↘︎")
                case .pageUp: text.append("⇞")
                case .pageDown: text.append("⇟")
                case .clear: text.append("⌧")
                case .tab: text.append("⇥")
                case .space: text.append("␣")
                case .return: text.append("⏎")
                default:
                    if character == "\u{7f}" {
                        text.append("⌫")
                    } else {
                        text.append(character.uppercased())
                    }
                }
            }
            return text
        }
    }
    
    @ViewBuilder
    func idleView(forMeasurement: Bool = false) -> some View {
        let shortcut = Shortcut(from: keyBinding)
        
        HStack {
            if forMeasurement {
                clickToRecordLabel
            } else if shortcut.key.isEmpty {
                clickToRecordLabel
                    .onTapGesture(perform: startRecording)
            } else {
                Text(shortcut.stringRepresentation)
            }
            
            Button("Edit", systemImage: "square.and.pencil", action: startRecording)
                .labelStyle(.iconOnly)
                .disabled(forMeasurement)
        }
    }
    
    var clickToRecordLabel: some View {
        Text("Click to record")
    }
    
    @ViewBuilder
    var recordingView: some View {
        // A stable container is required so the `ShortcutCaptureNSView` instance
        // does not change when `onModifier` is called for the first time.
        // A `Group` doesn't cut it, must be a real container.
        // Alternative would be to ditch the `if` but the second text is
        // actually a localizable text, so has a different type than the
        // shortcut string representation.
        ZStack {
            if let inFlightShortcut, !inFlightShortcut.isEmpty {
                Text(inFlightShortcut.stringRepresentation)
            } else {
                Text("Recording…")
            }
        }
        .padding(.horizontal)
        .overlay {
            ShortcutCaptureView { modifiers in
                var shortcut = inFlightShortcut ?? Shortcut()
                shortcut.modifiers = modifiers
                inFlightShortcut = shortcut
                
            } onKey: { key in
                var keyBinding = self.keyBinding
                keyBinding.key = key
                keyBinding.modifiers = inFlightShortcut?.modifiers ?? []
                
                update(keyBinding)
                // The rest shouldn't be needed, the `update` side effect should
                // already replace the view. Still, abort the edit.
                inFlightShortcut = nil
                state = .idle
                
            } onCancel: {
                inFlightShortcut = nil
                state = .idle
            }
        }
    }
    
    func startRecording() {
        inFlightShortcut = nil
        state = .recording
    }
    
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onModifiers: (TerminalKeyModifiers) -> Void
    let onKey: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        ShortcutCaptureNSView()
    }

    func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
        view.onModifiers = onModifiers
        view.onKey = onKey
        view.onCancel = onCancel
    }
}

// Needs to be non-private so that ``SettingsEscapeKeyHandler`` can detect it.
internal final class ShortcutCaptureNSView: NSView {
    var onModifiers: (TerminalKeyModifiers) -> Void = { _ in }
    var onKey: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Immediately make this view the first responde so we can record the
        // key presses.
        self.window?.makeFirstResponder(self)
    }

    override func flagsChanged(with event: NSEvent) {
        onModifiers(modifiers(for: event))
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        guard let character = event.charactersIgnoringModifiers else { return }
        
        let modifiers = modifiers(for: event)
        if let char = character.first, KeyEquivalent(char) == .escape, modifiers.isEmpty {
            // A lone escape key cancels recording.
            onCancel()
            return
        }
        
        onModifiers(modifiers)
        onKey(character)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onCancel()
        }
        return accepted
    }
    
    private func modifiers(for event: NSEvent) -> TerminalKeyModifiers {
        var modifiers: TerminalKeyModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
    
}
