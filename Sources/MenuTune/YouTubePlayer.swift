import AppKit
import WebKit

/// The app owns this player for its entire lifetime, independently of the popover.
@MainActor
final class YouTubePlayer: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onEvent: (([String: Any]) -> Void)?
    private let identityURL = URL(string: "https://de.wdnhfr.menutune/")!
    private var loaded = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 236), configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "menuTune")
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func initialize() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.module.url(forResource: "player", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else {
            onEvent?(["kind": "resourceError"])
            return
        }
        // YouTube documents an HTTPS base URL using the app ID for native embeds.
        webView.loadHTMLString(html, baseURL: identityURL)
    }

    func command(_ name: String, arguments: [Any] = []) {
        guard ["load", "cue", "play", "pause", "stop", "volume", "seek"].contains(name),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.mt && window.mt.\(name)(...\(json))") { [weak self] _, error in
            if let error { self?.onEvent?(["kind": "commandError", "message": error.localizedDescription]) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "menuTune", message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.host == identityURL.host,
              let payload = message.body as? [String: Any] else { return }
        onEvent?(payload)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(["https", "about"].contains(url.scheme ?? "") ? .allow : .cancel)
        } else if url.absoluteString == "about:blank" || url.host == identityURL.host {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { openExternal(url) }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openExternal(url) }
        return nil
    }

    private func openExternal(_ url: URL) {
        guard ["https", "http"].contains(url.scheme ?? "") else { return }
        NSWorkspace.shared.open(url)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onEvent?(["kind": "networkError", "message": error.localizedDescription])
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        onEvent?(["kind": "terminated"])
    }

    func reload() {
        loaded = false
        initialize()
    }

    func shutdown() {
        command("stop")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "menuTune")
        webView.stopLoading()
    }
}
