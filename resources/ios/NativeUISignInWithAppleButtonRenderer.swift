import AuthenticationServices
import SwiftUI

/// Apple's own Sign in with Apple button. A tap only fires `on_press`; the
/// app starts the sign-in itself (usually through a social auth plugin), so
/// this element never runs an `ASAuthorizationController`.
///
/// Why UIKit's `ASAuthorizationAppleIDButton` and not SwiftUI's
/// `SignInWithAppleButton`: the SwiftUI button's only initialiser takes
/// `onRequest` and `onCompletion`, and every tap performs the Apple ID
/// request itself. It can't be used as a plain tap target, so a press would
/// start a second, competing request next to the app's. The UIKit button is
/// the same system-drawn control, with the same artwork, titles and styles.
///
/// The UIKit button only draws. The tap goes through a SwiftUI `Button`,
/// which feeds its pressed state back so the system highlight still shows.
/// A UIKit target-action would never fire here: core's root view has tap
/// gestures for dismissing the keyboard, and when they recognise a tap they
/// cancel the touch in any UIKit control underneath. SwiftUI controls
/// compose with those gestures instead.
///
/// Props:
///   - `label`: sign_in (default) | continue | sign_up
///   - `button_style`: auto (default) | black | white | white_outline.
///     `auto` follows the colour scheme: black in light mode, white in dark.
///   - `corner_radius`: points, clamped to half the height (a capsule).
///     The system default when absent.
///   - `disabled`
///   - `a11y_label`, `a11y_hint`: override the system's VoiceOver text.
///
/// Height comes from the node's layout (`height`, `h-*`), 44pt when unset.
/// Width follows the parent's proposal like any other control (`w-full`
/// to fill), 280pt when nothing is proposed. Children are an Android-only
/// fallback and are ignored here.
struct NativeUISignInWithAppleButtonRenderer: View {
    let node: NativeUINode

    @Environment(\.colorScheme) private var colorScheme

    static let defaultHeight: CGFloat = 44
    static let defaultWidth: CGFloat = 280

    var body: some View {
        let p = node.props
        let pressCb = p.getCallbackId("on_press")
        let nodeId = node.id
        let type = Self.buttonType(p.getString("label", default: "sign_in"))
        let a11yLabel = p.getString("a11y_label")
        let a11yHint = p.getString("a11y_hint")
        let disabled = p.getBool("disabled")

        Button {
            guard pressCb != 0 else { return }
            // Through the focus policy so a focused field's pending change
            // reaches PHP before the press does, as for <button>.
            KeyboardFocusPolicy.dispatchPress {
                NativeElementBridge.sendPressEvent(pressCb, nodeId: nodeId)
            }
        } label: {
            NativeUIAppleIDButton(
                type: type,
                style: Self.buttonStyle(p.getString("button_style", default: "auto"), colorScheme: colorScheme),
                cornerRadius: p.has("corner_radius") ? CGFloat(p.getFloat("corner_radius")) : nil,
                followsProposedHeight: (node.layout?.heightMode ?? SizeMode.wrap) != SizeMode.wrap
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(NativeUIAppleIDButtonPressStyle())
        .disabled(disabled)
        // The system button looks the same when disabled, so dim it.
        .opacity(disabled ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel.isEmpty ? NativeUIAppleIDButtonHost.title(for: type) : a11yLabel)
        .accessibilityHint(a11yHint)
        .accessibilityAddTraits(.isButton)
    }

    static func buttonType(_ label: String) -> ASAuthorizationAppleIDButton.ButtonType {
        switch label {
        case "continue": return .continue
        case "sign_up": return .signUp
        default: return .signIn
        }
    }

    static func buttonStyle(_ style: String, colorScheme: ColorScheme) -> ASAuthorizationAppleIDButton.Style {
        switch style {
        case "black": return .black
        case "white": return .white
        case "white_outline": return .whiteOutline
        default: return colorScheme == .dark ? .white : .black
        }
    }
}

/// Hands the SwiftUI button's pressed state to the UIKit button underneath,
/// which draws its own highlight.
private struct NativeUIAppleIDButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.nativeUIAppleIDButtonPressed, configuration.isPressed)
    }
}

private struct NativeUIAppleIDButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var nativeUIAppleIDButtonPressed: Bool {
        get { self[NativeUIAppleIDButtonPressedKey.self] }
        set { self[NativeUIAppleIDButtonPressedKey.self] = newValue }
    }
}

private struct NativeUIAppleIDButton: UIViewRepresentable {
    let type: ASAuthorizationAppleIDButton.ButtonType
    let style: ASAuthorizationAppleIDButton.Style
    let cornerRadius: CGFloat?
    let followsProposedHeight: Bool

    func makeUIView(context: Context) -> NativeUIAppleIDButtonHost {
        NativeUIAppleIDButtonHost()
    }

    func updateUIView(_ host: NativeUIAppleIDButtonHost, context: Context) {
        host.configure(type: type, style: style)
        host.requestedCornerRadius = cornerRadius
        host.button.isEnabled = context.environment.isEnabled
        host.button.isHighlighted = context.environment.nativeUIAppleIDButtonPressed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeUIAppleIDButtonHost, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            ?? NativeUISignInWithAppleButtonRenderer.defaultWidth
        let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
        let height = followsProposedHeight
            ? (proposedHeight ?? NativeUISignInWithAppleButtonRenderer.defaultHeight)
            : NativeUISignInWithAppleButtonRenderer.defaultHeight

        return CGSize(width: width, height: height)
    }
}

/// Holds the Apple ID button and swaps it for a new one when the type or
/// style changes, since both are fixed when the button is created. Touches
/// and VoiceOver go to the SwiftUI button around it.
final class NativeUIAppleIDButtonHost: UIView {
    private(set) var button: ASAuthorizationAppleIDButton
    private var type: ASAuthorizationAppleIDButton.ButtonType = .signIn
    private var style: ASAuthorizationAppleIDButton.Style = .black
    private var systemCornerRadius: CGFloat

    private static var titles: [ASAuthorizationAppleIDButton.ButtonType: String] = [:]

    var requestedCornerRadius: CGFloat? {
        didSet {
            if requestedCornerRadius != oldValue { setNeedsLayout() }
        }
    }

    init() {
        button = ASAuthorizationAppleIDButton(authorizationButtonType: type, authorizationButtonStyle: style)
        systemCornerRadius = button.cornerRadius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The system's title for a button type, in the device's language
    /// ("Sign in with Apple"), for VoiceOver on the SwiftUI button.
    static func title(for type: ASAuthorizationAppleIDButton.ButtonType) -> String {
        if let title = titles[type] {
            return title
        }

        let title = ASAuthorizationAppleIDButton(authorizationButtonType: type, authorizationButtonStyle: .black)
            .accessibilityLabel ?? "Sign in with Apple"
        titles[type] = title

        return title
    }

    func configure(type: ASAuthorizationAppleIDButton.ButtonType, style: ASAuthorizationAppleIDButton.Style) {
        guard type != self.type || style != self.style else { return }

        self.type = type
        self.style = style
        let replacement = ASAuthorizationAppleIDButton(authorizationButtonType: type, authorizationButtonStyle: style)
        replacement.isEnabled = button.isEnabled
        button.removeFromSuperview()
        button = replacement
        systemCornerRadius = replacement.cornerRadius
        addSubview(replacement)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.frame = bounds
        button.cornerRadius = requestedCornerRadius.map { min(max($0, 0), bounds.height / 2) } ?? systemCornerRadius
    }
}
