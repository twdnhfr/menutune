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
    let webView: WKWebView
    var isActive = true

    func makeNSView(context: Context) -> PlayerWebViewHost {
        let host = PlayerWebViewHost()
        if isActive { host.attach(webView) }
        return host
    }

    func updateNSView(_ host: PlayerWebViewHost, context: Context) {
        if isActive { host.attach(webView) }
        else { host.detach() }
    }

    static func dismantleNSView(_ host: PlayerWebViewHost, coordinator: ()) {
        host.detach()
    }
}
