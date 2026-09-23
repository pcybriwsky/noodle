import AppKit
import WebKit

/// Floating panel that never becomes key, so it can't take keyboard focus.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click land on a button even though the panel is never key or active.
final class CardWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Hosts card.html. Swift -> JS via window.showCard / window.setSubtitle, JS -> Swift via
/// webkit.messageHandlers.posture.postMessage({action}). See card.html for the contract.
@MainActor
final class CardController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onAction: ((String) -> Void)?
    private(set) var isVisible = false

    private let panel: CardPanel
    private let webView: CardWebView
    private var ready = false
    private var queued: (() -> Void)?
    private var baseCard = CGSize(width: 340, height: 132)   // overridden by window.CARD in card.html
    private var card = CGSize(width: 340, height: 132)       // current size, grows when "How to" opens
    private var pad: CGFloat = 24                            // transparent margin for the CSS shadow
    private var anchorTop = true                             // which edge stays put when the card resizes
    private var generation = 0

    init(resources: URL) {
        let cfg = WKWebViewConfiguration()
        webView = CardWebView(frame: .zero, configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        panel = CardPanel(contentRect: NSRect(x: 0, y: 0, width: 388, height: 180),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(self, name: "posture")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentView = webView
        webView.navigationDelegate = self
        webView.loadFileURL(resources.appendingPathComponent("card.html"), allowingReadAccessTo: resources)
    }

    /// `function` is the card.html entry point: showCard for exercises, showWelcome for the intro.
    func show(payload: [String: Any], position: String, inset: CGFloat, function: String = "showCard") {
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let js = "window.\(function)(\(String(decoding: data, as: UTF8.self)))"
        let run = { [weak self] in
            guard let self else { return }
            self.webView.evaluateJavaScript(js) { _, err in
                if let err { debug("showCard failed: \(err)") }
                self.present(position: position, inset: inset)
            }
        }
        isVisible = true
        if ready { run() } else { queued = run }
    }

    func setSubtitle(_ text: String) {
        webView.evaluateJavaScript("window.setSubtitle(\(json(text)))")
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        queued = nil
        generation += 1
        let g = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == g else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func present(position: String, inset: CGFloat) {
        guard isVisible else { return }
        generation += 1
        card = baseCard
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = NSSize(width: card.width + pad * 2, height: card.height + pad * 2)
        let top = !position.hasPrefix("bottom")
        anchorTop = top
        let x = position.hasSuffix("left") ? vf.minX + inset - pad : vf.maxX - inset - card.width - pad
        let y = top ? vf.maxY - inset - card.height - pad : vf.minY + inset - pad
        let final = NSRect(origin: NSPoint(x: x, y: y), size: size)
        panel.setFrame(final.offsetBy(dx: 0, dy: top ? 8 : -8), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let g = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                // Pin the end state exactly, in case the animation was cut short.
                guard let self, self.generation == g else { return }
                self.panel.alphaValue = 1
                self.panel.setFrame(final, display: true)
            }
        })
    }

    /// The card asked for a new height (the "How to" panel opened or closed). Keeps the edge
    /// nearest the screen corner fixed so the card grows away from it.
    private func resize(height: CGFloat) {
        guard isVisible, height > 0, abs(height - card.height) > 0.5 else { return }
        debug("card resize \(Int(card.height)) -> \(Int(height))")
        let old = panel.frame
        card.height = height
        let newH = height + pad * 2
        let y = anchorTop ? old.maxY - newH : old.minY
        let frame = NSRect(x: old.minX, y: y, width: old.width, height: newH)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: WKNavigationDelegate / WKScriptMessageHandler

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("JSON.stringify(window.CARD || null)") { [weak self] result, _ in
            guard let self else { return }
            if let s = result as? String,
               let m = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Double] {
                if let w = m["width"], let h = m["height"] { self.baseCard = CGSize(width: w, height: h) }
                if let p = m["pad"] { self.pad = p }
            }
            self.ready = true
            self.queued?()
            self.queued = nil
        }
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? [String: Any]
        let action = body?["action"] as? String ?? message.body as? String
        debug("card message \(action ?? "?")")
        if action == "resize" {
            if let h = body?["height"] as? Double { resize(height: CGFloat(h)) }
            return
        }
        if let action { onAction?(action) }
    }
}
