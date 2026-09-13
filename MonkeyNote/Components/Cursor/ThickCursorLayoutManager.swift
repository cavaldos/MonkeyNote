//
//  CursorLayoutManager.swift
//  MonkeyNote
//
//  Plain layout manager — no markdown rendering (removed for large-file performance).
//

#if os(macOS)
import AppKit

class CursorLayoutManager: NSLayoutManager {
    var cursorWidth: CGFloat = 6
}
#endif
