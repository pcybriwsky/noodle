import AppKit
import WebKit

/// Floating panel that never becomes key, so it can't take keyboard focus.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click land on a button even though the panel is never key or active.
final class CardWebView: WKWebView {
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// WKWebView only follows the mouse in the key window, and this panel never becomes key, so
    /// hover states never fired. An always-on tracking area hands it the moves itself.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
}

/// Hosts card.html. Swift -> JS via window.showCard / showWelcome / enter / leave / setSubtitle,
/// JS -> Swift via webkit.messageHandlers.posture.postMessage({action}). See card.html for the contract.
///
/// The window just sits where the card rests, sized to the card plus a transparent margin, and the
/// page does all the moving: slide in, height changes, celebrations, exits. It tells us when it's
/// done leaving ("gone") so the window can go.
@MainActor
final class CardController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var onAction: ((String) -> Void)?
    private(set) var isVisible = false   // a card is up, from show until hide

    private struct Margins { var t, r, b, l: CGFloat }

    private let panel: CardPanel
    private let webView: CardWebView
    private var ready = false
    private var queued: (() -> Void)?
    private var baseCard = CGSize(width: 340, height: 132)   // overridden by window.CARD in card.html
    private var cardHeight: CGFloat = 132                    // current height, grows when "How to" opens
    private var pad: CGFloat = 24                            // transparent margin for the CSS shadow
    private var margins = Margins(t: 24, r: 24, b: 24, l: 24)
    private var anchorTop = true                             // which edge stays put when the card resizes
    private var generation = 0
    private let dropper: Dropper
    private static let dropSeconds = 0.95

    init(resources: URL) {
        dropper = Dropper(resources: resources)
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
    /// The card slides in from the screen edge. With `dropSVG` and a top corner, the character rides a
    /// noodle down from the menu bar first and the card grows out of its tile where it lands. If a
    /// card is already up (the intro), the page swaps the new one in place.
    func show(payload: [String: Any], position: String, inset: CGFloat, function: String = "showCard",
              dropSVG: String? = nil) {
        let swapping = isVisible && panel.isVisible
        let top = !position.hasPrefix("bottom")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let drop = (top && !reduceMotion && !swapping) ? dropSVG : nil
        guard let l = layout(position: position, inset: inset) else { return }
        dropper.cancel()
        isVisible = true
        generation += 1

        var payload = payload
        payload["layout"] = ["t": l.margins.t, "r": l.margins.r, "b": l.margins.b, "l": l.margins.l,
                             "edge": position.hasSuffix("left") ? "left" : "right", "anchor": top ? "top" : "bottom"]
        payload["entrance"] = reduceMotion ? "fade" : (drop != nil ? "hold" : "slide")
        if dropSVG != nil && top { payload["noodle"] = inset }   // it hangs from the noodle it came down on
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        let js = "window.\(function)(\(String(decoding: data, as: UTF8.self)))"
        let tileFromTop: CGFloat = function == "showWelcome" ? 80 : 66   // figure tile center, from card top

        let run = { [weak self] in
            guard let self, self.isVisible else { return }
            if !swapping {
                self.margins = l.margins
                self.anchorTop = top
                self.cardHeight = self.baseCard.height
                self.panel.setFrame(l.frame, display: false)
                if drop == nil { self.orderIn() }   // the page is blank until it slides the card in
            }
            self.webView.evaluateJavaScript(js) { _, err in
                if let err { debug("\(function) failed: \(err)") }
            }
            if let svg = drop { self.dropIn(svg: svg, frame: l.frame, inset: inset, tileFromTop: tileFromTop) }
        }
        if ready { run() } else { queued = run }
    }

    func setSubtitle(_ text: String) {
        webView.evaluateJavaScript("window.setSubtitle(\(json(text)))")
    }

    /// Plays the exit for `reason` (done, snoozed, stopped, ignored, closed). The page posts "gone"
    /// when it's finished, and a timer covers it in case it never does.
    func hide(reason: String = "closed") {
        dropper.cancel()
        guard isVisible else { return }
        isVisible = false
        queued = nil
        generation += 1
        let g = generation
        guard panel.isVisible else { return }   // dismissed mid-drop, the card never came out
        webView.evaluateJavaScript("window.leave(\(json(reason)))")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.generation == g, !self.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    private func orderIn() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Where the card goes: on the screen with the mouse, `inset` from the corner. The window adds a
    /// margin for the shadow and reaches past the screen edge so the card can slide in from it (and
    /// up under the menu bar, for the noodle and the peek).
    private func layout(position: String, inset: CGFloat) -> (vf: NSRect, frame: NSRect, margins: Margins)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
        let vf = screen.visibleFrame
        let top = !position.hasPrefix("bottom"), left = position.hasSuffix("left")
        let edge = max(pad, inset + 8)
        let m = Margins(t: top ? edge : pad, r: left ? pad : edge, b: pad, l: left ? edge : pad)
        let cardX = left ? vf.minX + inset : vf.maxX - inset - baseCard.width
        let cardY = top ? vf.maxY - inset - baseCard.height : vf.minY + inset
        let frame = NSRect(x: cardX - m.l, y: cardY - m.b,
                           width: baseCard.width + m.l + m.r, height: baseCard.height + m.t + m.b)
        return (vf, frame, m)
    }

    /// A strip from the menu bar down past the card's figure tile, centered on the tile. The
    /// character lands on the tile, then the card grows out from under it and the strip fades.
    private func dropIn(svg: String, frame: NSRect, inset: CGFloat, tileFromTop: CGFloat) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else { return orderIn() }
        let vf = screen.visibleFrame
        let tileCenterX = frame.minX + margins.l + 14 + 52
        let landY = inset + tileFromTop                      // tile center, measured down from the menu bar
        let height = landY + 70
        let strip = NSRect(x: tileCenterX - 70, y: vf.maxY - height, width: 140, height: height)
        let g = generation
        dropper.drop(svg: svg, strip: strip, landY: landY, duration: Self.dropSeconds) { [weak self] in
            guard let self, self.isVisible, self.generation == g else { return }
            self.orderIn()
            self.webView.evaluateJavaScript("window.enter('bloom')")
            self.dropper.finish()
        }
    }

    /// The card asked for a new height. Keeps the edge nearest the screen corner fixed so the card
    /// grows away from it, then tells the page there's room.
    private func resize(height: CGFloat, id: Int) {
        defer { webView.evaluateJavaScript("window.resized && window.resized(\(id))") }
        guard isVisible, height > 0, abs(height - cardHeight) > 0.5 else { return }
        let old = panel.frame
        cardHeight = height
        let newH = height + margins.t + margins.b
        let y = anchorTop ? old.maxY - newH : old.minY
        panel.setFrame(NSRect(x: old.minX, y: y, width: old.width, height: newH), display: true)
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
        switch action {
        case "resize":
            let h = body?["height"] as? Double ?? 0
            resize(height: CGFloat(h), id: body?["id"] as? Int ?? 0)
        case "gone":
            debug("card gone")
            if !isVisible { panel.orderOut(nil) }
        case "hover":
            onAction?((body?["value"] as? Bool ?? false) ? "hover:on" : "hover:off")
        case "focus":
            if let value = body?["value"] as? String { onAction?("focus:\(value)") }
        case let action?:
            debug("card message \(action)")
            onAction?(action)
        case nil:
            break
        }
    }
}
