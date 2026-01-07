//
//  SearchNavigation.swift
//  MonkeyNote
//
//  Extension for search result navigation
//

#if os(macOS)
import AppKit

// MARK: - Search Navigation
extension CursorTextView {
    
    /// Navigate to a specific search match by index
    func navigateToMatch(index: Int) {
        guard index >= 0 && index < searchMatchRanges.count else { return }
        
        let matchRange = searchMatchRanges[index]
        
        // Set flag before selecting to prevent toolbar from showing
        isNavigatingSearch = true
        
        // Select the match
        setSelectedRange(matchRange)
        
        // Reset flag
        isNavigatingSearch = false
        
        // Scroll to make it visible
        scrollRangeToVisible(matchRange)
        
        // Update highlights to show new current match
        currentSearchIndex = index
        updateHighlights()
        
        // Apply pulse animation to current match highlight
        pulseCurrentMatchHighlight()
    }
    
    // MARK: - Pulse Animation for Current Match (Scale up then back)
    func pulseCurrentMatchHighlight() {
        // Apply pulse animation only to current match layers (orange ones)
        for layer in currentMatchLayers {
            // Set anchor point to center for proper scaling
            let bounds = layer.bounds
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            layer.bounds = bounds
            
            let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnimation.values = [1.0, 1.2, 1.0]  // Normal -> Scale up -> Back to normal
            scaleAnimation.keyTimes = [0, 0.2, 0.4]
            scaleAnimation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),      // Scale up quickly
                CAMediaTimingFunction(name: .easeInEaseOut) // Scale back smoothly
            ]
            scaleAnimation.duration = 0.25
            scaleAnimation.isRemovedOnCompletion = true
            layer.add(scaleAnimation, forKey: "pulse")
        }
    }
}
#endif
