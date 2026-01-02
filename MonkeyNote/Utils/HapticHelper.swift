//
//  HapticHelper.swift
//  MonkeyNote
//
//  Created by Assistant on 03/01/26.
//

import Foundation

#if os(iOS)
import UIKit

func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    let generator = UIImpactFeedbackGenerator(style: style)
    generator.impactOccurred()
}

func triggerNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(type)
}

#elseif os(macOS)
import AppKit

func triggerHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
}
#endif
