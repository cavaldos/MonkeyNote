//
//  Animation.swift
//  MonkeyNote
//
//  Extension for cursor animation (properties are in main class)
//  This file is kept for organizational purposes
//

#if os(macOS)
import AppKit

// MARK: - Smooth Caret (Monkeytype-style)
//
// Nguyên tắc từ skill animation-principles:
// - Chỉ animate GPU path: position + opacity (tránh frame/width/top/left)
// - Micro interaction 50-150ms, ease-out cubic-bezier(0,0,0.2,1)
// - Nhảy xa thì snap, gõ liền kề thì slide

extension CursorTextView {
    /// Khoảng cách tối đa vẫn slide. Xa hơn → snap ngay (click chuột, nhảy dòng xa).
    static let caretSnapThreshold: CGFloat = 100

    var caretReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var caretShouldAnimate: Bool {
        cursorAnimationEnabled && !caretReducedMotion
    }

    /// Monkeytype dùng anime.js ease "inOut(1.25)" (~ease-in-out).
    /// Ease-out cũ tạo cảm giác "dính" khi gõ nhanh; in-out lướt đều 2 đầu.
    static var caretTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    func shouldSnapCaret(from old: NSRect, to new: NSRect) -> Bool {
        if old == .zero { return true } // lần đầu hiện, không trượt từ gốc
        let dx = abs(new.origin.x - old.origin.x)
        let dy = abs(new.origin.y - old.origin.y)
        // Khác dòng xa (> 1 dòng) hoặc nhảy ngang xa → snap
        if dy > new.height * 1.5 { return true }
        return (dx + dy) > Self.caretSnapThreshold
    }

    /// Làm tròn về pixel vật lý — tránh caret mờ/nhòe khi dừng ở nửa pixel.
    func snapToPixel(_ p: CGPoint) -> CGPoint {
        let scale = window?.backingScaleFactor ?? 2
        return CGPoint(
            x: (p.x * scale).rounded() / scale,
            y: (p.y * scale).rounded() / scale
        )
    }

    /// Slide caret bằng position (GPU), size set cứng không animate.
    /// Cơ chế Monkeytype (elements/caret.ts): cancel animation cũ rồi retarget
    /// từ vị trí ĐANG THẤY (presentation), không phải đích cũ — gõ nhanh vẫn lướt
    /// liên tục thay vì giật về. Thêm requestAnimationFrame debounce bên web;
    /// bên này drawInsertionPoint đã coalesce theo display nên chỉ cần retarget đúng.
    func animateCaretLayer(to thickRect: NSRect) {
        guard let layer = cursorLayer else { return }
        let animated = caretShouldAnimate && !shouldSnapCaret(from: lastCursorRect, to: thickRect)

        // Vị trí mắt đang thấy (giữa animation cũ) — điểm bắt đầu của animation mới.
        // Đọc TRƯỚC khi set model value, nếu không sẽ luôn giật về đích cũ.
        let visualPosition = layer.presentation()?.position ?? layer.position
        let newPosition = snapToPixel(CGPoint(x: thickRect.midX, y: thickRect.midY))

        // Đo nhịp gõ: gõ burst (dt < duration) mà giữ nguyên 0.15s thì animation
        // chồng nhau, caret mãi tụt sau chữ. Co duration theo dt để kịp chữ mới.
        // Gõ tay nhịp thất thường (Telex chữ+dấu, ngắt nghỉ) → dt thô nhảy loạn,
        // duration nhảy theo gây giật. EMA làm mượt nhịp để caret giữ 1 tốc độ.
        let now = CACurrentMediaTime()
        let base = min(max(cursorAnimationDuration, 0.03), 0.2)
        let dt = lastCaretMoveTime > 0 ? now - lastCaretMoveTime : .greatestFiniteMagnitude
        lastCaretMoveTime = now
        if dt > base * 2 {
            smoothCaretDt = 0 // nghỉ hẳn: thoát burst, nhát gõ sau bay ease đầy đủ
            smoothCaretDist = 0
        } else if smoothCaretDt == 0 {
            smoothCaretDt = dt
        } else {
            smoothCaretDt += (dt - smoothCaretDt) * 0.3
        }
        // Giữ burst qua cú ngập ngừng ngắn để khỏi flicker giữa linear/ease.
        let rhythm = smoothCaretDt > 0 ? smoothCaretDt : dt

        // Size set cứng, không cho implicit animation lẫn vào
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = NSRect(origin: .zero, size: thickRect.size).integral
        if !animated {
            layer.removeAnimation(forKey: "caretSlide")
            layer.position = newPosition
        }
        CATransaction.commit()

        guard animated else { return }

        // Gõ gần xong mà animation cũ còn bay → bỏ qua move quá nhỏ (<0.5px) cho đỡ rung,
        // nhưng VẪN đồng bộ model về chữ mới nhất — nếu return sớm mà không set
        // position thì caret kẹt lại phía sau khi gõ ký tự hẹp (i, l, .).
        if abs(visualPosition.x - newPosition.x) < 0.5
            && abs(visualPosition.y - newPosition.y) < 0.5 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "caretSlide")
            layer.position = newPosition
            CATransaction.commit()
            return
        }

        // EMA khoảng cách (chỉ move animate — snap teleport không tính để khỏi
        // nhiễu velocity). Cùng alpha với nhịp để 2 EMA song hành.
        let dist = hypot(newPosition.x - visualPosition.x, newPosition.y - visualPosition.y)
        if smoothCaretDist == 0 {
            smoothCaretDist = dist
        } else {
            smoothCaretDist += (dist - smoothCaretDist) * 0.3
        }

        // Clamp duration về dải micro 0.03...0.2s (skill: faster is better).
        // Gõ burst: NỚI LỎNG 4-5 chữ — duration theo nhịp EMA (không phải dt thô)
        // để lướt đều một cụm thay vì dí từng chữ. Dí từng chữ (duration <= dt
        // + ease có gia tốc) tạo stop-start liên tục → giật. Để duration > dt
        // thì caret tụt sau vài chữ lúc gõ nhanh rồi tự bắt kịp khi dừng,
        // retarget từ presentation với vận tốc gần như hằng số → mượt.
        // VẬN TỐC HẰNG SỐ: duration tỉ lệ khoảng cách (neo theo EMA: dist trung
        // bình đi hết burstDur) — chữ hẹp `i` đi nhanh tương ứng, chữ rộng `w`
        // đi lâu tương ứng, mắt thấy 1 tốc độ px/s thay vì lúc bò lúc nhảy.
        let isBurst = rhythm < base
        let burstDur = isBurst ? min(max(rhythm * 4, 0.06), base) : base
        let duration: TimeInterval
        if isBurst, smoothCaretDist > 0.5 {
            duration = min(max(burstDur * dist / smoothCaretDist, 0.03), base)
        } else {
            duration = burstDur
        }
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = visualPosition
        move.toValue = newPosition
        move.duration = duration
        // Burst: linear giữ vận tốc đều qua các lần retarget (không giật);
        // bình thường: in-out lướt đều 2 đầu.
        move.timingFunction = isBurst
            ? CAMediaTimingFunction(name: .linear)
            : Self.caretTimingFunction
        move.isRemovedOnCompletion = true
        move.fillMode = .forwards
        layer.position = newPosition
        layer.add(move, forKey: "caretSlide")
    }
}
#endif
