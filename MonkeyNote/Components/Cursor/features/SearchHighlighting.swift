//
//  SearchHighlighting.swift
//  MonkeyNote
//
//  Extension for search text highlighting with viewport-based optimization
//

#if os(macOS)
import AppKit

// MARK: - Search Highlighting (Viewport-Based Optimization)
extension CursorTextView {
    
    /// Main entry point - updates highlights based on current viewport
    func updateHighlights() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If search query changed, reset everything and start fresh
        if query != lastSearchQuery {
            resetSearch()
            lastSearchQuery = query
        }

        guard !query.isEmpty else {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(deferredSearch), object: nil)
            clearAllHighlights()
            onSearchMatchesChanged?(0, true)
            return
        }

        let text = self.string
        guard !text.isEmpty else {
            clearAllHighlights()
            onSearchMatchesChanged?(0, true)
            return
        }

        // Document may have been edited since last search (same query, stale
        // NSRanges) — didChangeText() marks isSearchComplete = false in that case.
        let needsResearch = !isSearchComplete
        if needsResearch {
            // Background search đang chạy trên snapshot: không restart khi scroll
            // (tránh livelock search không bao giờ xong), chỉ vẽ lại viewport.
            if isSearching {
                updateVisibleHighlights()
                return
            }
            // File lớn: gõ mỗi phím mà search lại cả doc thì lag → tối đa 1 lần/s,
            // giữa các lần giữ highlights cũ, chỉ update viewport.
            if isLargeDocument, Date().timeIntervalSince(lastFullSearchTime) < 1.0 {
                updateVisibleHighlights()
                return
            }
            // File vừa/lớn + vừa gõ trong doc: debounce 0.4s sau edit cuối, giữ
            // highlights cũ trong lúc gõ. Đổi query (flag false) thì search ngay.
            if isMediumOrLargeDocument, searchNeedsRefreshDueToEdit {
                updateVisibleHighlights()
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(deferredSearch), object: nil)
                perform(#selector(deferredSearch), with: nil, afterDelay: 0.4)
                return
            }
            performFullSearch(query: query, in: text)
        }

        // Update visible highlights (force full redraw after re-search,
        // otherwise viewport cache would keep stale layer frames)
        updateVisibleHighlights(force: needsResearch)
    }

    /// Gõ trong doc xong (debounce) → research thật. Flag hạ trước để lần gọi
    /// lồng nhau không schedule lại vô hạn (edit mới sẽ dựng flag lại).
    @objc func deferredSearch() {
        searchNeedsRefreshDueToEdit = false
        updateHighlights()
    }

    // Mỗi slice quét ngoài main — đủ nhỏ để không chiếm main, đủ lớn để ít hop.
    private static let searchSliceLength = 100_000

    /// Viewport-first search: PASS 1 sync vùng nhìn thấy (vẽ + navigate ngay),
    /// phần còn lại doc vừa/lớn quét chunked ngoài main, merge dần để scroll
    /// tới đâu hiện tới đó. Doc nhỏ quét nốt sync như cũ.
    func performFullSearch(query: String, in text: String) {
        searchTask?.cancel()
        isSearching = false
        searchNeedsRefreshDueToEdit = false
        allMatchRanges.removeAll()
        searchMatchRanges.removeAll()

        let ns = text as NSString
        let total = ns.length
        guard total > 0 else {
            isSearchComplete = true
            onSearchMatchesChanged?(0, true)
            return
        }

        // PASS 1 (sync, rẻ): vùng nhìn thấy + buffer — kết quả hiện ngay.
        let headRange = extendedVisibleCharRange(total: total)
            ?? NSRange(location: 0, length: min(total, 8192))
        let head = Self.ranges(of: query, in: ns, range: headRange)
        allMatchRanges = head
        searchMatchRanges = head
        // Partial notify: count tạm + isComplete=false (ViewModel đã hỗ trợ).
        onSearchMatchesChanged?(head.count, false)

        let rest = Self.subtracting(headRange, total: total)
        guard !rest.isEmpty else {
            finishSearch()
            return
        }

        // Doc nhỏ: quét nốt sync (không Task overhead, hành vi cũ giữ nguyên).
        if !isMediumOrLargeDocument {
            for r in rest {
                allMatchRanges.append(contentsOf: Self.ranges(of: query, in: ns, range: r))
            }
            allMatchRanges.sort { $0.location < $1.location }
            searchMatchRanges = allMatchRanges
            finishSearch()
            return
        }

        // Doc vừa/lớn: quét phần còn lại ngoài main theo slice. Snapshot string
        // (value type) nên background không chạm storage đang edit trên main.
        isSearching = true
        let snapshot = text
        let token = UUID()
        searchToken = token
        searchTask = Task { [weak self] in
            var pending: [NSRange] = []
            pending.reserveCapacity(256)
            for r in rest {
                var off = r.location
                let end = r.location + r.length
                while off < end {
                    if Task.isCancelled { return }
                    let len = min(Self.searchSliceLength, end - off)
                    pending.append(contentsOf: Self.ranges(
                        of: query, in: snapshot as NSString,
                        range: NSRange(location: off, length: len)))
                    off += len
                    // Merge theo đợt để viewport cập nhật dần (scroll hiện dần).
                    if pending.count >= 256 || off >= end {
                        let batch = pending
                        pending.removeAll(keepingCapacity: true)
                        await MainActor.run { [weak self] in
                            // Task cũ (bị cancel bởi edit/query mới) → bỏ batch stale.
                            guard let self, self.searchToken == token else { return }
                            self.allMatchRanges.append(contentsOf: batch)
                            self.allMatchRanges.sort { $0.location < $1.location }
                            self.searchMatchRanges = self.allMatchRanges
                            self.onSearchMatchesChanged?(self.allMatchRanges.count, false)
                            self.updateVisibleHighlights()
                        }
                    }
                    if Task.isCancelled { return }
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.searchToken == token else { return }
                self.isSearching = false
                self.finishSearch()
            }
        }
    }

    private func finishSearch() {
        isSearchComplete = true
        lastFullSearchTime = Date()
        onSearchMatchesChanged?(allMatchRanges.count, true)
    }
    
    /// Update highlights only for matches visible in viewport
    func updateVisibleHighlights(force: Bool = false) {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return }
        
        let visibleRect = self.visibleRect
        
        // Skip if viewport hasn't changed significantly (unless forced after re-search)
        if !force &&
           abs(visibleRect.origin.y - lastVisibleRect.origin.y) < 10 &&
           abs(visibleRect.size.height - lastVisibleRect.size.height) < 10 &&
           !highlightLayers.isEmpty {
            // Just update current match highlighting
            updateCurrentMatchHighlight()
            return
        }
        lastVisibleRect = visibleRect
        
        // Recycle existing layers
        recycleAllHighlightLayers()
        
        // Get visible character range with buffer
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        
        // Add buffer (half screen above and below)
        let bufferSize = visibleCharRange.length / 2
        let extendedStart = max(0, visibleCharRange.location - bufferSize)
        let extendedEnd = min(self.string.utf16.count, visibleCharRange.location + visibleCharRange.length + bufferSize)
        let extendedRange = NSRange(location: extendedStart, length: extendedEnd - extendedStart)
        
        // Ensure layout only for extended visible range
        layoutManager.ensureLayout(forCharacterRange: extendedRange)
        
        let origin = textContainerOrigin
        visibleHighlightedRanges.removeAll()

        // allMatchRanges luôn sorted theo location → binary search lấy đúng lát
        // cắt trong extended range: scroll tới đâu chỉ duyệt tới đó. Query phổ
        // biến ("e" → hàng chục nghìn matches) cũng không loop full mỗi frame.
        let extendedEndLoc = extendedRange.location + extendedRange.length
        var lo = Self.lowerBoundMatchEnd(allMatchRanges, extendedRange.location)
        // Lùi 1 bước nếu match ngay trước overlap vào trong (match dài).
        while lo > 0 {
            let prev = allMatchRanges[lo - 1]
            if prev.location + prev.length > extendedRange.location { lo -= 1 } else { break }
        }
        let hi = Self.upperBoundMatchStart(allMatchRanges, extendedEndLoc)

        // Only create layers for matches within extended visible range
        guard lo < hi else { return }
        for index in lo..<hi {
            let matchRange = allMatchRanges[index]
            // Overlap guard (match dài hơn extended range vẫn vẽ).
            let matchEnd = matchRange.location + matchRange.length
            guard matchRange.location < extendedEndLoc && matchEnd > extendedRange.location else {
                continue
            }

            visibleHighlightedRanges.insert(index)
            
            let glyphRange = layoutManager.glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { continue }
            
            let isCurrentMatch = index == currentSearchIndex
            
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                guard rect.width > 0 && rect.height > 0 else { return }
                
                let highlightLayer = self.reuseOrCreateLayer()
                let padding: CGFloat = isCurrentMatch ? 2.5 : 1.2
                let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
                
                // Configure layer appearance
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                if isCurrentMatch {
                    highlightLayer.backgroundColor = NSColor.orange.withAlphaComponent(0.6).cgColor
                    highlightLayer.borderWidth = 0
                    highlightLayer.borderColor = nil
                    self.currentMatchLayers.append(highlightLayer)
                } else {
                    highlightLayer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
                    highlightLayer.borderWidth = 0
                    highlightLayer.borderColor = nil
                }
                highlightLayer.cornerRadius = 2
                highlightLayer.frame = paddedRect.offsetBy(dx: origin.x, dy: origin.y)
                
                CATransaction.commit()
                
                self.layer?.addSublayer(highlightLayer)
                self.highlightLayers.append(highlightLayer)
            }
        }
    }
    
    /// Update only the current match highlight (for navigation without full redraw)
    func updateCurrentMatchHighlight() {
        // Clear previous current match styling
        for layer in currentMatchLayers {
            layer.backgroundColor = NSColor.yellow.withAlphaComponent(0.3).cgColor
            layer.borderWidth = 0
            layer.borderColor = nil
        }
        currentMatchLayers.removeAll()
        
        // Find and update current match layer if visible
        guard currentSearchIndex < allMatchRanges.count,
              visibleHighlightedRanges.contains(currentSearchIndex),
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let matchRange = allMatchRanges[currentSearchIndex]
        let glyphRange = layoutManager.glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return }
        
        let origin = textContainerOrigin
        
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
            guard rect.width > 0 && rect.height > 0 else { return }
            
            // Find existing layer at this position or create new one
            let padding: CGFloat = 2.5
            let paddedRect = rect.insetBy(dx: -padding, dy: -padding)
            let targetFrame = paddedRect.offsetBy(dx: origin.x, dy: origin.y)
            
            // Look for existing layer at this position
            for layer in self.highlightLayers {
                if layer.frame.intersects(targetFrame) {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.backgroundColor = NSColor.orange.withAlphaComponent(0.6).cgColor
                    layer.borderWidth = 0
                    layer.borderColor = nil
                    layer.cornerRadius = 2
                    layer.frame = targetFrame
                    CATransaction.commit()
                    self.currentMatchLayers.append(layer)
                    return
                }
            }
        }
    }
    
    /// Clear all highlights and reset state
    func clearAllHighlights() {
        recycleAllHighlightLayers()
        allMatchRanges.removeAll()
        searchMatchRanges.removeAll()
        visibleHighlightedRanges.removeAll()
        isSearchComplete = false
    }
    
    /// Reset search state (called when query changes)
    func resetSearch() {
        searchTask?.cancel()
        isSearching = false
        // Query mới → bỏ debounce-edit của query cũ, search query mới ngay.
        searchNeedsRefreshDueToEdit = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(deferredSearch), object: nil)
        clearAllHighlights()
        lastVisibleRect = .zero
    }
    
    // MARK: - Layer Pooling
    
    /// Get a layer from pool or create new one
    func reuseOrCreateLayer() -> CALayer {
        if let layer = layerPool.popLast() {
            return layer
        }
        return CALayer()
    }
    
    /// Recycle all highlight layers back to pool
    func recycleAllHighlightLayers() {
        for layer in highlightLayers {
            layer.removeFromSuperlayer()
            layerPool.append(layer)
        }
        highlightLayers.removeAll()
        currentMatchLayers.removeAll()

        // Limit pool size to prevent memory bloat
        if layerPool.count > 200 {
            layerPool.removeFirst(layerPool.count - 200)
        }
    }

    // MARK: - Viewport Helpers (static, O(log N) / O(slice))

    /// Vùng ký tự đang nhìn thấy + buffer nửa màn hình trên/dưới, clip theo total.
    /// nil khi layout chưa sẵn (đổi note) → caller fallback đầu doc.
    private func extendedVisibleCharRange(total: Int) -> NSRange? {
        guard let lm = layoutManager, let tc = textContainer, total > 0 else { return nil }
        let glyphRange = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return nil }
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let buf = charRange.length / 2
        let start = max(0, charRange.location - buf)
        let end = min(total, charRange.location + charRange.length + buf)
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// Tất cả matches của query trong đúng 1 range (không quét ngoài).
    private static func ranges(of query: String, in ns: NSString, range: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        var r = range
        let end = range.location + range.length
        while r.length > 0 {
            let f = ns.range(of: query, options: .caseInsensitive, range: r)
            if f.location == NSNotFound { break }
            out.append(f)
            let next = f.location + f.length
            if next >= end { break }
            r = NSRange(location: next, length: end - next)
        }
        return out
    }

    /// Phần bù của inner trong [0, total): tối đa 2 khúc (trước + sau viewport).
    private static func subtracting(_ inner: NSRange, total: Int) -> [NSRange] {
        var out: [NSRange] = []
        if inner.location > 0 {
            out.append(NSRange(location: 0, length: inner.location))
        }
        let tail = inner.location + inner.length
        if tail < total {
            out.append(NSRange(location: tail, length: total - tail))
        }
        return out
    }

    /// Index đầu tiên có matchEnd > value (binary search trên mảng sorted).
    private static func lowerBoundMatchEnd(_ matches: [NSRange], _ value: Int) -> Int {
        var lo = 0, hi = matches.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if matches[mid].location + matches[mid].length <= value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    /// Index đầu tiên có matchStart >= value (binary search trên mảng sorted).
    private static func upperBoundMatchStart(_ matches: [NSRange], _ value: Int) -> Int {
        var lo = 0, hi = matches.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            if matches[mid].location < value {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
#endif
