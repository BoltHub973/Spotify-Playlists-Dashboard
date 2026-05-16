import Cocoa

/// Full-window panel shown when the user is not yet authenticated with Spotify.
/// Opens the OAuth flow in the system browser (WKWebView often fails to render
/// Spotify's accounts pages), then polls /api/auth-status until the token is
/// captured by the Flask /callback route.
class AuthRequiredViewController: NSObject {

    private let containerView: NSView
    private let onAuthenticated: () -> Void

    private var statusLabel: NSTextField!
    private var signInButton: NSButton!
    private var pollTimer: Timer?

    private let loginURL = URL(string: "http://127.0.0.1:8888/login")!
    private let statusURL = URL(string: "http://127.0.0.1:8888/api/auth-status")!

    init(parentView: NSView, onAuthenticated: @escaping () -> Void) {
        self.onAuthenticated = onAuthenticated

        containerView = NSView(frame: parentView.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0).cgColor

        super.init()

        parentView.addSubview(containerView, positioned: .above, relativeTo: nil)
        buildContent()
    }

    private func buildContent() {
        let brand = label("SPOTIFY DASHBOARD",
                          font: NSFont(name: "Menlo-Bold", size: 16) ?? NSFont.boldSystemFont(ofSize: 16),
                          color: NSColor(red: 0.52, green: 1.0, blue: 0.0, alpha: 1.0))
        brand.alignment = .center

        let heading = label("Connect Your Spotify Account",
                            font: NSFont.systemFont(ofSize: 32, weight: .bold),
                            color: .white)
        heading.alignment = .center

        let intro = wrappingLabel(
            "Spotify Dashboard needs permission to read your playlists. " +
            "Click the button below to sign in — your browser will open Spotify's login page. " +
            "After you approve access, this app will automatically continue.",
            font: NSFont.systemFont(ofSize: 14),
            color: NSColor(white: 0.8, alpha: 1.0)
        )
        intro.alignment = .center

        signInButton = NSButton(title: "Sign In with Spotify", target: self, action: #selector(signIn))
        signInButton.bezelStyle = .rounded
        signInButton.keyEquivalent = "\r"
        signInButton.controlSize = .large
        signInButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)

        statusLabel = wrappingLabel("",
                                    font: NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                    color: NSColor(white: 0.55, alpha: 1.0))
        statusLabel.alignment = .center

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .centerX
        outer.spacing = 16
        outer.translatesAutoresizingMaskIntoConstraints = false

        outer.addArrangedSubview(brand)
        outer.setCustomSpacing(12, after: brand)
        outer.addArrangedSubview(heading)
        outer.setCustomSpacing(10, after: heading)
        outer.addArrangedSubview(intro)
        outer.setCustomSpacing(28, after: intro)
        outer.addArrangedSubview(signInButton)
        outer.setCustomSpacing(20, after: signInButton)
        outer.addArrangedSubview(statusLabel)

        containerView.addSubview(outer)

        let contentWidth: CGFloat = 520

        NSLayoutConstraint.activate([
            outer.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            outer.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            outer.widthAnchor.constraint(equalToConstant: contentWidth),

            intro.widthAnchor.constraint(equalTo: outer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: outer.widthAnchor),
        ])
    }

    @objc private func signIn() {
        NSWorkspace.shared.open(loginURL)
        signInButton.title = "Waiting for browser sign-in…"
        signInButton.isEnabled = false
        statusLabel.stringValue = "Once you approve in Spotify, this window will continue automatically."
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkAuthStatus()
        }
        // Fire immediately too
        checkAuthStatus()
    }

    private func checkAuthStatus() {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 2.0
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let authed = json["authenticated"] as? Bool, authed
            else { return }

            DispatchQueue.main.async {
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.dismiss {
                    self.onAuthenticated()
                }
            }
        }.resume()
    }

    func dismiss(_ completion: (() -> Void)? = nil) {
        pollTimer?.invalidate()
        pollTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            containerView.animator().alphaValue = 0
        }, completionHandler: {
            self.containerView.removeFromSuperview()
            completion?()
        })
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = font
        f.textColor = color
        f.isBezeled = false
        f.isEditable = false
        f.drawsBackground = false
        return f
    }

    private func wrappingLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let f = NSTextField(wrappingLabelWithString: text)
        f.font = font
        f.textColor = color
        f.isBezeled = false
        f.isEditable = false
        f.drawsBackground = false
        return f
    }
}
