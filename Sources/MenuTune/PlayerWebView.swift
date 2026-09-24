import AppKit
import SwiftUI
import WebKit

/// A host owns the placement, not the lifetime, of the shared player.
@MainActor
final class PlayerWebViewHost: NSView {
    private weak var hostedView: WKWebView?

    func attach(_ webView: WKWebView) {
        hostedView = webView
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    func detach() {
        // SwiftUI can dismantle its host after the player has moved to the panel.
        // Never detach a view that now belongs to the other host.
        if hostedView?.superview === self { hostedView?.removeFromSuperview() }
        hostedView = nil
    }
}

struct YouTubeWebView: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> PlayerWebViewHost {
        let host = PlayerWebViewHost()
        update(host)
        return host
    }

    func updateNSView(_ host: PlayerWebViewHost, context: Context) {
        update(host)
    }

    /// SwiftUI still updates this view once after the pop-out has taken the
    /// player, just before it dismantles it. A flag captured with the view
    /// would be stale by then and pull the player back, so read it live.
    private func update(_ host: PlayerWebViewHost) {
        if model.isPoppedOut { host.detach() }
        else { host.attach(model.player.webView) }
    }

    static func dismantleNSView(_ host: PlayerWebViewHost, coordinator: ()) {
        host.detach()
    }
}
