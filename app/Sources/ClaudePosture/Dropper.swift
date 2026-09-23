import AppKit
import WebKit

/// The noodle drop: a transparent strip hanging from the menu bar that clicks pass straight
/// through. The character rides a spaghetti strand down to the card's spot, then the card takes over.
@MainActor
final class Dropper: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let panel: CardPanel
    private let webView: WKWebView
    private var ready = false
    private var queued: (() -> Void)?
    private var onArrive: (() -> Void)?
    private var generation = 0

    init(resources: URL) {
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        panel = CardPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 200),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        cfg.userContentController.add(self, name: "dropper")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = webView
        webView.navigationDelegate = self
        webView.loadFileURL(resources.appendingPathComponent("drop.html"), allowingReadAccessTo: resources)
    }

    /// Drops the character inside `strip` (screen coords, top edge at the menu bar) so its 96pt
    /// box lands centered `landY` points below the top. Calls `arrived` once, even if the page never answers.
    func drop(svg: String, strip: NSRect, landY: CGFloat, duration: Double, arrived: @escaping () -> Void) {
        generation += 1
        let g = generation
        onArrive = arrived
        let args: [String: Any] = ["svg": svg, "landY": landY, "duration": duration]
        let data = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
        let run = { [weak self] in
            guard let self, self.generation == g else { return }
            self.panel.setFrame(strip, display: true)
            self.panel.alphaValue = 1
            self.panel.orderFrontRegardless()
            self.webView.evaluateJavaScript("window.drop(\(String(decoding: data, as: UTF8.self)))")
        }
        if ready { run() } else { queued = run }
        Task { [weak self] in   // safety net if the page never posts "arrived"
            try? await Task.sleep(nanoseconds: UInt64((duration + 1.5) * 1_000_000_000))
            guard let self, self.generation == g else { return }
            self.arrive()
        }
    }

    /// Fades the rig out as the card appears in its place.
    func finish() {
        let g = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == g else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Stops a drop in progress without calling back (the card was dismissed mid-drop).
    func cancel() {
        generation += 1
        onArrive = nil
        queued = nil
        panel.orderOut(nil)
    }

    private func arrive() {
        let cb = onArrive
        onArrive = nil
        cb?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        queued?()
        queued = nil
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "arrived" { arrive() }
    }
}
