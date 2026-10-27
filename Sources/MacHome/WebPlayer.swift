import AppKit
import WebKit

/// Shows a "web" tile full screen inside MacHome, with its own user agent and codec limits.
final class WebPlayer: NSObject, WKNavigationDelegate, WKUIDelegate {
    let entry: LauncherEntry
    let window: FullScreenWindow
    private let webView: WKWebView
    /// Called when the page closes itself, e.g. after "Exit YouTube".
    var onClose: (() -> Void)?
    private var closed = false

    init(entry: LauncherEntry, url: URL, frame: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        if !entry.blockCodecs.isEmpty {
            let script = WKUserScript(source: WebPlayer.codecFilter(entry.blockCodecs),
                                      injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        }
        let webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        if let userAgent = entry.userAgent, !userAgent.isEmpty {
            webView.customUserAgent = userAgent
        }
        self.webView = webView
        self.window = FullScreenWindow(frame: frame)
        self.entry = entry
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.load(URLRequest(url: url))
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
    }

    func close() {
        guard !closed else { return }
        closed = true
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Sends a key press to the page as if typed, without needing Accessibility access.
    func sendKey(_ key: SynthKey) {
        guard let characters = key.characters else { return }
        if window.firstResponder !== webView { window.makeFirstResponder(webView) }
        for type in [NSEvent.EventType.keyDown, NSEvent.EventType.keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: key.localFlags,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: key.keyCode) else { continue }
            NSApp.postEvent(event, atStart: false)
        }
    }

    func scroll(dx: Int32, dy: Int32) {
        guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0),
              let event = NSEvent(cgEvent: cgEvent) else { return }
        webView.scrollWheel(with: event)
    }

    // MARK: - WKUIDelegate

    func webViewDidClose(_ webView: WKWebView) {
        onClose?()
    }

    /// Opens links meant for a new window in this one, since there is only one window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func showError(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads and interrupted frame loads happen during normal redirects.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
        let html = """
        <html><body style="background:#000;color:#fff;font:32px -apple-system,sans-serif;\
        display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;text-align:center">
        <div style="font-size:48px;font-weight:700;margin-bottom:24px">Couldn't open \(WebPlayer.escape(entry.title))</div>
        <div style="opacity:.8;max-width:70%">\(WebPlayer.escape(nsError.localizedDescription))</div>
        <div style="opacity:.6;margin-top:40px">Press Home, or View and Menu together, to go back.</div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Makes the page believe the listed codecs are unsupported, so sites fall back to H.264 (the same
    /// approach as the h264ify extension). This Mac's Haswell graphics only decode H.264 in hardware.
    private static func codecFilter(_ codecs: [String]) -> String {
        let lowercased = codecs.map { $0.lowercased() }
        let data = (try? JSONSerialization.data(withJSONObject: lowercased)) ?? Data("[]".utf8)
        let list = String(data: data, encoding: .utf8) ?? "[]"
        return """
        (function () {
          var blocked = \(list);
          function isBlocked(type) {
            if (typeof type !== 'string') { return false; }
            var lower = type.toLowerCase();
            for (var i = 0; i < blocked.length; i++) {
              if (lower.indexOf(blocked[i]) !== -1) { return true; }
            }
            return false;
          }
          function wrapIsTypeSupported(source) {
            if (!source || typeof source.isTypeSupported !== 'function') { return; }
            var original = source.isTypeSupported.bind(source);
            source.isTypeSupported = function (type) { return isBlocked(type) ? false : original(type); };
          }
          wrapIsTypeSupported(window.MediaSource);
          wrapIsTypeSupported(window.ManagedMediaSource);
          wrapIsTypeSupported(window.WebKitMediaSource);
          if (window.HTMLMediaElement) {
            var canPlayType = HTMLMediaElement.prototype.canPlayType;
            HTMLMediaElement.prototype.canPlayType = function (type) {
              return isBlocked(type) ? '' : canPlayType.call(this, type);
            };
          }
          var capabilities = navigator.mediaCapabilities;
          if (capabilities && typeof capabilities.decodingInfo === 'function') {
            var decodingInfo = capabilities.decodingInfo.bind(capabilities);
            capabilities.decodingInfo = function (config) {
              var video = config && config.video && config.video.contentType;
              var audio = config && config.audio && config.audio.contentType;
              if (isBlocked(video) || isBlocked(audio)) {
                return Promise.resolve({ supported: false, smooth: false, powerEfficient: false });
              }
              return decodingInfo(config);
            };
          }
        })();
        """
    }
}
