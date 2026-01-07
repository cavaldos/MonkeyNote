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
    
    func startBlinkTimer() {
        stopBlinkTimer()
        guard cursorBlinkEnabled else { return }
        
        cursorVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.cursorVisible.toggle()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.cursorLayer?.opacity = self.cursorVisible ? 1 : 0
            CATransaction.commit()
        }
    }
    
    func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
    
    func resetBlinkTimer() {
        // Reset the blink cycle - show cursor and restart timer
        cursorVisible = true
        cursorLayer?.opacity = 1
        if cursorBlinkEnabled {
            startBlinkTimer()
        }
    }
}
#endif
