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

        // Gõ gần xong mà animation cũ còn bay → bỏ qua move quá nhỏ (<0.5px) cho đỡ rung
        if abs(visualPosition.x - newPosition.x) < 0.5
            && abs(visualPosition.y - newPosition.y) < 0.5 {
            return
        }

        // Clamp duration về dải micro 0.03...0.2s (skill: faster is better)
        let duration = min(max(cursorAnimationDuration, 0.03), 0.2)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = visualPosition
        move.toValue = newPosition
        move.duration = duration
        move.timingFunction = Self.caretTimingFunction
        move.isRemovedOnCompletion = true
        move.fillMode = .forwards
        layer.position = newPosition
        layer.add(move, forKey: "caretSlide")
    }
}
#endif
