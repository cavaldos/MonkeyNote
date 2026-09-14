//
//  CursorBlink.swift
//  MonkeyNote
//
//  Extension for cursor blinking functionality
//

#if os(macOS)
import AppKit

// MARK: - Cursor Blinking
extension CursorTextView {
    
    /// Giữ caret hiện rõ 0.8s sau mỗi phím gõ (kiểu Monkeytype), rồi mới blink tiếp.
    static let caretBlinkPause: TimeInterval = 0.8
    /// Fade blink mềm thay vì cắt cứng (skill: ease-out, 50-150ms).
    static let caretBlinkFade: Double = 0.08

    func setCaretOpacity(_ value: Float, animated: Bool) {
        guard let layer = cursorLayer else { return }
        if !animated || caretReducedMotion {
            // Model đã đúng giá trị → khỏi transaction (mũi tên/gõ gọi liên tục).
            guard layer.opacity != value else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = value
            CATransaction.commit()
            return
        }
        // Đọc opacity đang thấy để fade tiếp — tránh chớp khi toggle đúng lúc slide.
        // Chỉ đọc presentation khi thật sự animate (sync render server, đắt).
        let visualOpacity = layer.presentation()?.opacity ?? layer.opacity
        guard visualOpacity != value || layer.opacity != value
                || layer.animation(forKey: "caretBlink") == nil else { return }
        layer.removeAnimation(forKey: "caretBlink")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = visualOpacity
        fade.toValue = value
        fade.duration = Self.caretBlinkFade
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fade.isRemovedOnCompletion = true
        fade.fillMode = .forwards
        layer.opacity = value
        layer.add(fade, forKey: "caretBlink")
    }

    func startBlinkTimer() {
        stopBlinkTimer()
        guard cursorBlinkEnabled else { return }
        // Selection active -> keep thick caret hidden (it lives at the anchor).
        if selectedRange().length > 0 {
            hideCaretLayer()
            return
        }

        cursorVisible = true
        setCaretOpacity(1, animated: false)
        // scheduledTimer mặc định chỉ chạy ở .default mode → khựng khi scroll/gõ
        // (event tracking). Add vào .common để blink đều, không dồn burst gây giật.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // A running timer must not resurrect the anchor caret mid-selection.
            if self.selectedRange().length > 0 {
                self.hideCaretLayer()
                return
            }
            self.cursorVisible.toggle()
            self.setCaretOpacity(self.cursorVisible ? 1 : 0, animated: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    func resetBlinkTimer() {
        // Don't resurrect the anchor caret in the middle of a selection.
        if selectedRange().length > 0 {
            hideCaretLayer()
            return
        }
        // Reset the blink cycle - show cursor and restart timer.
        // Reuse the timer via fireDate: recreating a Timer on every cursor
        // move (i.e. every keystroke) costs a runloop add/remove each time.
        cursorVisible = true
        setCaretOpacity(1, animated: false)
        guard cursorBlinkEnabled else { return }
        if let timer = blinkTimer, timer.isValid {
            timer.fireDate = Date().addingTimeInterval(Self.caretBlinkPause)
        } else {
            startBlinkTimer()
        }
    }
}
#endif
