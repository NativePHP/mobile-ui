import AuthenticationServices
import SwiftUI

/// SwiftUI's own `SignInWithAppleButton`. Tapping it runs the Apple ID
/// request, as the system button always does, and the result goes to PHP as
/// a native event: `Native\Mobile\UI\Events\SignInWithAppleCompleted` or
/// `SignInWithAppleFailed`. `on_press` fires as the request starts.
///
/// Props:
///   - `label`: sign_in (default) | continue | sign_up
///   - `button_style`: auto (default) | black | white | white_outline.
///     `auto` follows the colour scheme: black in light mode, white in dark.
///   - `corner_radius`: points, clamped to half the height (a capsule).
///     The system default when absent.
///   - `scopes`: any of `email`, `full_name`. None by default.
///   - `nonce`: sent to Apple as given, and echoed on the completed event.
///     Apps pass the SHA-256 of a raw nonce they keep, so the raw value
///     never sits in the UI tree; Apple's identity token carries the hash.
///   - `state`: echoed back on both events.
///   - `disabled`
///   - `a11y_label`, `a11y_hint`: override the system's VoiceOver text.
///
/// Height comes from the node's layout (`height`, `h-*`), 44pt when unset.
/// Width follows the parent's proposal like any other control (`w-full`
/// to fill). Children are an Android-only fallback and are ignored here.
struct NativeUISignInWithAppleButtonRenderer: View {
    let node: NativeUINode

    @Environment(\.colorScheme) private var colorScheme

    static let defaultHeight: CGFloat = 44
    static let completedEvent = "Native\\Mobile\\UI\\Events\\SignInWithAppleCompleted"
    static let failedEvent = "Native\\Mobile\\UI\\Events\\SignInWithAppleFailed"

    var body: some View {
        let p = node.props
        let pressCb = p.getCallbackId("on_press")
        let nodeId = node.id
        let scopes = p.getStringList("scopes")
        let nonce = p.getString("nonce")
        let state = p.getString("state")
        let disabled = p.getBool("disabled")
        let a11yLabel = p.getString("a11y_label")
        let a11yHint = p.getString("a11y_hint")
        let styleName = Self.styleName(p.getString("button_style", default: "auto"), colorScheme: colorScheme)
        let explicitHeight = (node.layout?.heightMode ?? SizeMode.wrap) != SizeMode.wrap

        SignInWithAppleButton(Self.label(p.getString("label", default: "sign_in"))) { request in
            request.requestedScopes = scopes.compactMap(Self.scope)
            if !nonce.isEmpty {
                request.nonce = nonce
            }
            if !state.isEmpty {
                request.state = state
            }
            if pressCb != 0 {
                // Through the focus policy so a focused field's pending
                // change reaches PHP before the press does, as for <button>.
                KeyboardFocusPolicy.dispatchPress {
                    NativeElementBridge.sendPressEvent(pressCb, nodeId: nodeId)
                }
            }
        } onCompletion: { result in
            Self.send(result, nonce: nonce, state: state)
        }
        .signInWithAppleButtonStyle(Self.buttonStyle(styleName))
        // Rebuild when the style flips with the colour scheme: the system
        // button keeps the style it was first drawn with.
        .id(styleName)
        .frame(maxWidth: .infinity)
        .frame(height: explicitHeight ? nil : Self.defaultHeight)
        .frame(maxHeight: explicitHeight ? .infinity : nil)
        .modifier(CornerRadiusModifier(radius: p.has("corner_radius") ? CGFloat(p.getFloat("corner_radius")) : nil, outlined: styleName == "white_outline"))
        .disabled(disabled)
        // The system button looks the same when disabled, so dim it.
        .opacity(disabled ? 0.4 : 1)
        .modifier(A11yModifier(label: a11yLabel, hint: a11yHint))
    }

    static func label(_ label: String) -> SignInWithAppleButton.Label {
        switch label {
        case "continue": return .continue
        case "sign_up": return .signUp
        default: return .signIn
        }
    }

    /// `auto` resolved against the colour scheme.
    static func styleName(_ style: String, colorScheme: ColorScheme) -> String {
        switch style {
        case "black", "white", "white_outline": return style
        default: return colorScheme == .dark ? "white" : "black"
        }
    }

    static func buttonStyle(_ name: String) -> SignInWithAppleButton.Style {
        switch name {
        case "white": return .white
        case "white_outline": return .whiteOutline
        default: return .black
        }
    }

    static func scope(_ scope: String) -> ASAuthorization.Scope? {
        switch scope {
        case "email": return .email
        case "full_name": return .fullName
        default: return nil
        }
    }

    /// Sends the result to PHP as a native event. Optional values go as null.
    static func send(_ result: Result<ASAuthorization, Error>, nonce: String, state: String) {
        func value(_ string: String?) -> Any {
            guard let string, !string.isEmpty else { return NSNull() }
            return string
        }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                LaravelBridge.shared.send?(failedEvent, [
                    "code": "invalid_response",
                    "message": "Apple returned a credential that isn't an Apple ID.",
                    "state": value(state),
                ])
                return
            }

            LaravelBridge.shared.send?(completedEvent, [
                "userId": credential.user,
                "identityToken": value(credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }),
                "authorizationCode": value(credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }),
                "email": value(credential.email),
                "givenName": value(credential.fullName?.givenName),
                "familyName": value(credential.fullName?.familyName),
                "nonce": value(nonce),
                "state": value(credential.state ?? state),
                "realUserStatus": realUserStatus(credential.realUserStatus),
            ])

        case .failure(let error):
            LaravelBridge.shared.send?(failedEvent, [
                "code": code(error),
                "message": error.localizedDescription,
                "state": value(state),
            ])
        }
    }

    static func code(_ error: Error) -> String {
        guard let error = error as? ASAuthorizationError else { return "unknown" }

        switch error.code {
        case .canceled: return "canceled"
        case .failed: return "failed"
        case .invalidResponse: return "invalid_response"
        case .notHandled: return "not_handled"
        case .notInteractive: return "not_interactive"
        default: return "unknown"
        }
    }

    static func realUserStatus(_ status: ASUserDetectionStatus) -> String {
        switch status {
        case .likelyReal: return "likely_real"
        case .unknown: return "unknown"
        default: return "unsupported"
        }
    }
}

/// Clips to the requested corner radius, capped at a capsule. The white
/// outline is drawn again on top, since clipping cuts the system's own
/// outline at the corners.
private struct CornerRadiusModifier: ViewModifier {
    let radius: CGFloat?
    let outlined: Bool

    func body(content: Content) -> some View {
        if let radius {
            content.overlay {
                GeometryReader { proxy in
                    let shape = RoundedRectangle(cornerRadius: min(max(radius, 0), proxy.size.height / 2), style: .continuous)
                    if outlined {
                        shape.strokeBorder(Color.black, lineWidth: 1)
                    }
                }
            }
            .mask {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: min(max(radius, 0), proxy.size.height / 2), style: .continuous)
                }
            }
        } else {
            content
        }
    }
}

private struct A11yModifier: ViewModifier {
    let label: String
    let hint: String

    func body(content: Content) -> some View {
        content
            .modifier(OptionalLabel(label: label))
            .modifier(OptionalHint(hint: hint))
    }

    private struct OptionalLabel: ViewModifier {
        let label: String
        func body(content: Content) -> some View {
            if label.isEmpty { content } else { content.accessibilityLabel(label) }
        }
    }

    private struct OptionalHint: ViewModifier {
        let hint: String
        func body(content: Content) -> some View {
            if hint.isEmpty { content } else { content.accessibilityHint(hint) }
        }
    }
}
