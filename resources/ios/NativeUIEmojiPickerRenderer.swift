import SwiftUI
import UIKit

/// Emoji picker — the system emoji keyboard, raised while `visible` is true.
///
/// iOS has no public emoji picker view. What it offers (and what Messages'
/// "any emoji" Tapback uses) is the emoji keyboard itself: search, every
/// category, frequently used, and skin tones. So the renderer draws nothing
/// and keeps a hidden text field that asks for the emoji input mode; while
/// it's first responder the keyboard is the picker. Each emoji typed goes to
/// PHP as a select-change event (`on_change`) and never stays in the field.
///
/// `on_dismiss` fires when the person closes the keyboard themselves — the
/// Done bar above it, or a tap elsewhere — never when PHP sets `visible`
/// false. If the person has removed the emoji keyboard in Settings, the
/// field falls back to their default keyboard and anything that isn't an
/// emoji is ignored.
struct NativeUIEmojiPickerRenderer: View {
    let node: NativeUINode

    var body: some View {
        EmojiPickerField(
            visible: node.props.getBool("visible"),
            doneLabel: node.props.getString("done_label", default: "Done"),
            onChangeCb: node.props.getCallbackId("on_change"),
            onDismissCb: node.props.getCallbackId("on_dismiss"),
            a11yLabel: node.props.getString("a11y_label"),
            nodeId: node.id
        )
        .frame(width: 0, height: 0)
    }
}

private struct EmojiPickerField: UIViewRepresentable {
    let visible: Bool
    let doneLabel: String
    let onChangeCb: Int
    let onDismissCb: Int
    let a11yLabel: String
    let nodeId: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> NativeUIEmojiTextField {
        let field = NativeUIEmojiTextField(frame: .zero)
        field.coordinator = context.coordinator
        return field
    }

    func updateUIView(_ field: NativeUIEmojiTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.doneLabel = doneLabel
        coordinator.onChangeCb = onChangeCb
        coordinator.onDismissCb = onDismissCb
        coordinator.nodeId = nodeId
        field.accessibilityLabel = a11yLabel.isEmpty ? nil : a11yLabel
        coordinator.setVisible(visible, field: field)
    }

    static func dismantleUIView(_ field: NativeUIEmojiTextField, coordinator: Coordinator) {
        coordinator.wanted = false
        if field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator {
        var doneLabel = "Done"
        var onChangeCb = 0
        var onDismissCb = 0
        var nodeId = 0

        /// What PHP asked for in the last render. Cleared before the
        /// renderer resigns the field itself, so that blur isn't reported
        /// as the person closing the picker.
        var wanted = false

        let accessoryToken = UUID()

        func setVisible(_ visible: Bool, field: NativeUIEmojiTextField) {
            guard visible != wanted else { return }
            wanted = visible

            if visible {
                focusWhenReady(field, attempts: 40)
            } else if field.isFirstResponder {
                field.resignFirstResponder()
            }
        }

        /// A sheet that closes in the same render as the picker opens takes
        /// first responder back with it as it goes, so wait for any
        /// presentation in flight to settle before raising the keyboard.
        private func focusWhenReady(_ field: NativeUIEmojiTextField, attempts: Int) {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.wanted, !field.isFirstResponder else { return }

                guard field.window != nil, !Self.presentationInFlight(field), field.becomeFirstResponder() else {
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.focusWhenReady(field, attempts: attempts - 1)
                        }
                    }
                    return
                }

                NativeUIKeyboardAccessoryState.shared.claim(id: self.accessoryToken, title: self.doneLabel) { [weak self, weak field] in
                    guard let self, let field else { return }
                    self.closedByPerson(field)
                }
            }
        }

        private static func presentationInFlight(_ field: UIView) -> Bool {
            var controller = field.window?.rootViewController
            while let current = controller {
                if current.isBeingPresented || current.isBeingDismissed || current.transitionCoordinator != nil {
                    return true
                }
                controller = current.presentedViewController
            }
            return false
        }

        func picked(_ emoji: String) {
            guard wanted, onChangeCb != 0 else { return }
            NativeUIBridge.sendSelectChangeEvent(onChangeCb, nodeId: nodeId, value: emoji)
        }

        /// Done on the bar: the keyboard goes down and PHP hears about it.
        func closedByPerson(_ field: NativeUIEmojiTextField) {
            guard field.isFirstResponder else { return }
            field.resignFirstResponder()
        }

        /// Any blur the renderer didn't cause (Done, a tap elsewhere, another
        /// field taking focus) is the person closing the picker.
        func didResign() {
            NativeUIKeyboardAccessoryState.shared.release(id: accessoryToken)

            guard wanted else { return }
            wanted = false
            if onDismissCb != 0 {
                NativeUIBridge.sendSheetDismissEvent(onDismissCb, nodeId: nodeId)
            }
        }
    }
}

/// A field that only ever shows the emoji keyboard, and hands each emoji on
/// instead of keeping it.
final class NativeUIEmojiTextField: UITextField {
    fileprivate weak var coordinator: EmojiPickerField.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        tintColor = .clear
        textColor = .clear
        autocorrectionType = .no
        spellCheckingType = .no
        smartInsertDeleteType = .no
        inlinePredictionType = .no
        // Genmoji and stickers are images, not text a server can store.
        supportsAdaptiveImageGlyph = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The emoji keyboard, when the person has it. iOS only honours this
    /// with a context identifier, or it reopens whichever keyboard was used
    /// last.
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override var textInputContextIdentifier: String? { "" }

    override func insertText(_ text: String) {
        guard let first = text.first, first.nativeUIIsEmoji else { return }
        coordinator?.picked(String(first))
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            coordinator?.didResign()
        }
        return resigned
    }

    // Nothing to edit: no caret menu, no paste.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}

private extension Character {
    /// Emoji rather than text that happens to have an emoji form: digits,
    /// `#` and `*` are emoji bases only with a keycap after them.
    var nativeUIIsEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        return first.properties.isEmoji && (unicodeScalars.count > 1 || first.value > 0xFF)
    }
}
