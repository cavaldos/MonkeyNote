//
//  EditFade.swift
//  MonkeyNote
//
//  Fade thoáng qua cho chữ vừa gõ / vừa xóa để khớp với caret đang trượt.
//  - Xóa: snapshot điểm ảnh thật (chụp TRƯỚC khi xóa) rồi fade-out tại chỗ —
//    lấp khoảng trống khi caret còn tụt phía sau.
//  - Gõ nối cuối dòng: snapshot nền TRƯỚC khi chữ hiện, phủ lên rồi fade tấm
//    phủ (reveal) — chữ mờ dần vào cùng nhịp caret thay vì hiện trước.
//  - Còn lại (giữa dòng/paste/IME): chớp highlight mờ sau chữ rồi fade.
//  Chỉ animate opacity (GPU), duration lấy cùng nhịp caret burst.
//  Pool 12 layer ảnh dùng chung cho bóng xóa + màn reveal (mỗi vệt 1 timeline
//  riêng; dùng chung 1 layer sẽ reset opacity liên tục).
//

#if os(macOS)
import AppKit

extension CursorTextView {
    static let editFlashPeak: Float = 0.35

    /// Duration khớp caret hiện tại (burst → ~4 nhịp gõ EMA, xem Animation.swift).
    func caretFadeDuration() -> TimeInterval {
        let base = min(max(cursorAnimationDuration, 0.03), 0.2)
        let now = CACurrentMediaTime()
        let rawDt = lastCaretMoveTime > 0 ? now - lastCaretMoveTime : .greatestFiniteMagnitude
        let rhythm = smoothCaretDt > 0 ? smoothCaretDt : rawDt
        if rhythm < base { return min(max(rhythm * 4, 0.06), base) }
        return base
    }

    func rectForCharacterRange(_ range: NSRange) -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer,
              let ts = textStorage,
              range.location + range.length <= ts.length else { return nil }
        lm.ensureLayout(forCharacterRange: range)
        let glyphRange = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return nil }
        var r = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        guard r.width > 0.5, r.height > 0 else { return nil }
        r.origin.x += textContainerInset.width
        r.origin.y += textContainerInset.height
        return r.integral
    }

    /// Fade về 0 từ opacity ĐANG THẤY (presentation) — gõ/xóa burst retarget
    /// liên tục mà không bật tắt (không chớp). Idle mới dựng lại từ peak.
    func fadeLayerToZero(_ layer: CALayer, peak: Float, duration: TimeInterval) {
        let visual = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "editFade")
        let from: Float
        if visual < 0.05 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = peak
            CATransaction.commit()
            from = peak
        } else {
            from = visual
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = from
        a.toValue = 0
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        a.isRemovedOnCompletion = true
        a.fillMode = .forwards
        layer.opacity = 0
        layer.add(a, forKey: "editFade")
    }

    /// Pool layer ảnh dùng chung cho bóng xóa + màn reveal.
    /// Idle ⇒ không còn animation nên lấy ra dùng ngay an toàn.
    func dequeueFadeLayer() -> CALayer? {
        if let reused = editFadeIdle.popLast() { return reused }
        guard editFadeLayers.count < 12 else { return nil } // burst cạn — bỏ 1 vệt
        let l = CALayer()
        l.actions = [
            "opacity": NSNull(), "position": NSNull(), "bounds": NSNull(),
            "frame": NSNull(), "contents": NSNull()
        ]
        wantsLayer = true
        self.layer?.addSublayer(l)
        editFadeLayers.append(l)
        return l
    }

    func recycleFadeLayer(_ layer: CALayer) {
        if !editFadeIdle.contains(where: { $0 === layer }) {
            editFadeIdle.append(layer)
        }
    }

    /// Chụp vùng rect, giấu caret lúc chụp để ảnh không dính vệt đỏ.
    /// Giấu/hiện trong cùng runloop nên màn hình thật không chớp.
    func snapshotExcludingCaret(of rect: NSRect) -> CGImage? {
        guard bounds.intersects(rect),
              let rep = bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer?.isHidden = true
        CATransaction.commit()
        cacheDisplay(in: rect, to: rep)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer?.isHidden = false
        CATransaction.commit()
        return rep.cgImage
    }

    /// Chữ vừa gõ: chớp highlight mờ sau chữ, fade cùng nhịp caret.
    func flashInsertedCharacters(in range: NSRange) {
        guard caretShouldAnimate, let rect = rectForCharacterRange(range) else { return }
        if editFlashLayer == nil {
            let l = CALayer()
            l.cornerRadius = 2
            l.actions = [
                "opacity": NSNull(), "position": NSNull(), "bounds": NSNull(),
                "frame": NSNull(), "backgroundColor": NSNull()
            ]
            wantsLayer = true
            self.layer?.addSublayer(l)
            editFlashLayer = l
        }
        guard let l = editFlashLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.backgroundColor = insertionPointColor.withAlphaComponent(0.35).cgColor
        l.frame = rect.insetBy(dx: -1, dy: -1)
        CATransaction.commit()
        fadeLayerToZero(l, peak: Self.editFlashPeak, duration: caretFadeDuration())
    }

    /// Chữ vừa xóa: snapshot ĐIỂM ẢNH THẬT (đã chụp TRƯỚC khi xóa) rồi fade —
    /// khớp pixel tuyệt đối (không lệch như vẽ lại bằng CATextLayer: boundingRect
    /// là khung bó sát glyph còn text layer vẽ từ điểm pen, lệch ~1px + làm tròn).
    /// Bóng đặc như chữ thật, nán 30% đầu rồi tan; tổng hơn caret một chút để
    /// chữ "đợi" caret trượt tới. Mỗi ký tự một layer + timeline riêng (pool 12)
    /// nên giữ delete nhanh tạo vệt dissolve khớp caret.
    func flashDeletedImage(_ image: CGImage, at rect: NSRect) {
        guard caretShouldAnimate, let layer = dequeueFadeLayer() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "editFade")
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = image
        layer.frame = rect
        layer.opacity = 1
        CATransaction.commit()

        // Giữ đặc 30% đầu (delay ngắn) rồi tan nhanh — tổng chỉ hơn caret
        // một chút để chữ vừa kịp "đợi" caret mà không ì.
        let total = caretFadeDuration() + 0.03
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.3, 1]
        fade.duration = total
        fade.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeOut)
        ]
        fade.isRemovedOnCompletion = true
        fade.fillMode = .forwards
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let self, let layer else { return }
            self.recycleFadeLayer(layer)
        }
        layer.opacity = 0
        layer.add(fade, forKey: "editFade")
        CATransaction.commit()
    }

    /// Điểm pen nơi chữ sắp hiện — chỉ khi gõ NỐI CUỐI DÒNG (giữa dòng chữ
    /// cũ tràn sang phải, snapshot nền sẽ sai nên trả nil để dùng highlight).
    /// Trả rect rộng 0, cao 1 dòng tại pen; caller cộng thêm rộng chữ.
    func lineEndPenRect(at loc: Int) -> NSRect? {
        guard let lm = layoutManager, let ts = textStorage,
              loc <= ts.length else { return nil }
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0))
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineRange.location, ns.character(at: lineEnd - 1) == 0xA {
            lineEnd -= 1 // trừ \n cuối dòng
        }
        guard loc == lineEnd else { return nil }
        let origin = textContainerOrigin
        if loc > lineRange.location {
            let g = lm.glyphIndexForCharacter(at: loc - 1)
            let used = lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)
            guard used.width > 0, used.height > 0 else { return nil }
            return NSRect(x: origin.x + used.maxX, y: origin.y + used.minY,
                          width: 0, height: used.height)
        }
        // Dòng trống: pen ở đầu fragment
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        if ts.length == 0 {
            let h = ceil(font.ascender - font.descender)
            return NSRect(x: origin.x, y: origin.y, width: 0, height: h)
        }
        let g = lm.glyphIndexForCharacter(at: min(loc, ts.length - 1))
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        return NSRect(x: origin.x + frag.minX, y: origin.y + frag.minY,
                      width: 0, height: frag.height)
    }

    /// PHẦN 1 (gọi TRƯỚC super.insertText): đo chỗ chữ sắp hiện + snapshot nền.
    /// Trả (ảnh nền, rect phủ) để phần 2 reveal sau khi chữ đã vào.
    func planInsertCover(_ str: String, at loc: Int) -> (CGImage, NSRect)? {
        guard caretShouldAnimate,
              let pen = lineEndPenRect(at: loc) else { return nil }
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        let w = ceil((str as NSString).size(withAttributes: [.font: font]).width) + 2
        guard w > 2 else { return nil }
        let rect = NSRect(x: pen.minX, y: pen.minY, width: w, height: pen.height).integral
        guard let bg = snapshotExcludingCaret(of: rect) else { return nil }
        return (bg, rect)
    }

    /// PHẦN 2 (gọi SAU super.insertText): phủ nền lên chữ mới rồi fade tấm phủ —
    /// chữ mờ dần vào cùng nhịp caret. Tan ngay không giữ (reveal càng nhanh càng thật).
    func showInsertCover(_ plan: (CGImage, NSRect)) {
        guard let layer = dequeueFadeLayer() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "editFade")
        layer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = plan.0
        layer.frame = plan.1
        layer.opacity = 1
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let self, let layer else { return }
            self.recycleFadeLayer(layer)
        }
        fadeLayerToZero(layer, peak: 1, duration: caretFadeDuration())
        CATransaction.commit()
    }
}
#endif
