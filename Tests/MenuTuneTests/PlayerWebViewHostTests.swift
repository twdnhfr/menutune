import AppKit
import WebKit
import XCTest
@testable import MenuTune

final class PlayerWebViewHostTests: XCTestCase {
    func testLatePopoverDetachDoesNotRemoveFloatingPlayer() async {
        await MainActor.run {
            let webView = WKWebView()
            let menuHost = PlayerWebViewHost(frame: NSRect(x: 0, y: 0, width: 448, height: 252))
            let floatingHost = PlayerWebViewHost(frame: NSRect(x: 0, y: 0, width: 192, height: 108))
            menuHost.attach(webView)
            floatingHost.attach(webView)

            // The previous SwiftUI host may be dismantled after the panel takes over.
            menuHost.detach()
            XCTAssertTrue(webView.superview === floatingHost)
            XCTAssertEqual(webView.frame, floatingHost.bounds)

            menuHost.attach(webView)
            floatingHost.detach()
            XCTAssertTrue(webView.superview === menuHost)
            XCTAssertEqual(webView.frame, menuHost.bounds)
            menuHost.detach()
        }
    }
}
