//
//  PomodoroTimerView.swift
//  MonkeyNote
//
//  Created by Nguyen Ngoc Khanh on 29/12/24.
//

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Pomodoro Timer Manager (ObservableObject - Isolated from ContentView)

final class PomodoroTimerManager: ObservableObject {
    static let shared = PomodoroTimerManager()
    
    @Published var timeRemaining: Int = 0 // seconds
    @Published var isRunning: Bool = false
    @Published var showInput: Bool = false
    @Published var minutesInput: String = ""
    
    private var timer: Timer?
    
    private init() {}
    
    func startInput() {
        showInput = true
    }
    
    func start() {
        // If input is empty, use default 25 minutes
        let minutes = Int(minutesInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 25
        guard minutes > 0 else { return }
        
        timeRemaining = minutes * 60
        isRunning = true
        showInput = false
        
        // Start timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stop()
                // Play sound when timer completes
                #if os(macOS)
                NSSound.beep()
                #endif
            }
        }
        
        triggerPomodoroHaptic()
    }
    
    func pause() {
        isRunning = false
        timer?.invalidate()
        triggerPomodoroHaptic()
    }
    
    func resume() {
        isRunning = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stop()
                #if os(macOS)
                NSSound.beep()
                #endif
            }
        }
        
        triggerPomodoroHaptic()
    }
    
    func stop() {
        isRunning = false
        timer?.invalidate()
        timeRemaining = 0
        minutesInput = ""
        triggerPomodoroHaptic()
    }
    
    func cancelInput() {
        showInput = false
        minutesInput = ""
    }
    
    func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    private func triggerPomodoroHaptic() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        #elseif os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

// MARK: - Pomodoro Timer View (Isolated - Won't trigger ContentView re-render)

struct PomodoroTimerView: View {
    @StateObject private var manager = PomodoroTimerManager.shared
    @AppStorage("note.isDarkMode") private var isDarkMode: Bool = true
    
    var body: some View {
        HStack(spacing: 6) {
            // Timer display or input
            if manager.timeRemaining > 0 {
                // Show countdown
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundStyle(manager.isRunning ? .orange : .secondary)
                    
                    Text(manager.formatTime(manager.timeRemaining))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(isDarkMode ? .white.opacity(0.9) : .black.opacity(0.9))
                }
                
                // Pause/Resume button
                Button {
                    if manager.isRunning {
                        manager.pause()
                    } else {
                        manager.resume()
                    }
                } label: {
                    Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Stop button
                Button {
                    manager.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if manager.showInput {
                // Show input field
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                
                #if os(macOS)
                TextField("25", text: $manager.minutesInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 50)
                    .onSubmit {
                        manager.start()
                    }
                    .onExitCommand {
                        // Handle Esc key
                        manager.cancelInput()
                    }
                #else
                TextField("25", text: $manager.minutesInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .keyboardType(.numberPad)
                #endif
                
                // Start button
                Button {
                    manager.start()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                        .foregroundStyle(isDarkMode ? .white : .black)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Cancel button
                Button {
                    manager.cancelInput()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Show timer icon button
                Button {
                    manager.startInput()
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Start Pomodoro timer")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        )
        .animation(.spring(response: 0.20, dampingFraction: 0.5), value: manager.timeRemaining)
        .animation(.spring(response: 0.20, dampingFraction: 0.5), value: manager.showInput)
        .animation(.spring(response: 0.20, dampingFraction: 0.5), value: manager.isRunning)
    }
}

#Preview {
    PomodoroTimerView()
        .padding()
}
