//
//  FileWatcherService.swift
//  MonkeyNote
//
//  Created by Assistant on 21/02/26.
//

import Foundation

/// Monitors files and vault directory for external changes (other editors, cloud sync, etc.)
/// Uses polling with modification date comparison for reliability with atomic writes.
final class FileWatcherService {
    
    // MARK: - File Monitoring
    
    private var fileTimer: DispatchSourceTimer?
    private var watchedFileURL: URL?
    private var lastKnownFileModDate: Date?
    private var suppressUntil: Date = .distantPast
    
    /// Called on main thread when the watched file's content changes externally.
    var onFileContentChanged: ((String) -> Void)?
    
    // MARK: - Vault Monitoring
    
    private var vaultTimer: DispatchSourceTimer?
    private var watchedVaultURL: URL?
    private var lastVaultSnapshotHash: Int = 0
    
    /// Called on main thread when vault structure changes (files added/removed/renamed).
    var onVaultStructureChanged: (() -> Void)?
    
    // MARK: - File Watching
    
    /// Start watching a specific file for external changes.
    /// - Parameters:
    ///   - url: The file URL to watch
    ///   - interval: Check interval in seconds (default 0.5s for responsive sync)
    func watchFile(at url: URL, interval: TimeInterval = 0.5) {
        stopWatchingFile()
        
        watchedFileURL = url
        lastKnownFileModDate = modificationDate(of: url)
        
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkFileForChanges()
        }
        timer.resume()
        fileTimer = timer
    }
    
    /// Stop watching the current file.
    func stopWatchingFile() {
        fileTimer?.cancel()
        fileTimer = nil
        watchedFileURL = nil
        lastKnownFileModDate = nil
    }
    
    /// Call before saving to suppress change detection for our own writes.
    func notifyWillSave() {
        suppressUntil = Date().addingTimeInterval(1.5)
    }
    
    /// Call after saving to update the known modification date.
    func notifyDidSave() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let url = self.watchedFileURL else { return }
            self.lastKnownFileModDate = self.modificationDate(of: url)
        }
    }
    
    // MARK: - Vault Watching
    
    /// Start watching the vault directory for structural changes.
    /// - Parameters:
    ///   - url: The vault root directory URL
    ///   - interval: Check interval in seconds (default 3s)
    func watchVault(at url: URL, interval: TimeInterval = 3.0) {
        stopWatchingVault()
        
        watchedVaultURL = url
        lastVaultSnapshotHash = snapshotHash(of: url)
        
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkVaultForChanges()
        }
        timer.resume()
        vaultTimer = timer
    }
    
    /// Stop watching the vault directory.
    func stopWatchingVault() {
        vaultTimer?.cancel()
        vaultTimer = nil
        watchedVaultURL = nil
        lastVaultSnapshotHash = 0
    }
    
    /// Update the vault snapshot after we made changes ourselves.
    func updateVaultSnapshot() {
        guard let url = watchedVaultURL else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.lastVaultSnapshotHash = self?.snapshotHash(of: url) ?? 0
        }
    }
    
    /// Stop all monitoring.
    func stopAll() {
        stopWatchingFile()
        stopWatchingVault()
    }
    
    deinit {
        stopAll()
    }
    
    // MARK: - Private: File Change Detection
    
    private func checkFileForChanges() {
        guard Date() > suppressUntil else { return }
        guard let url = watchedFileURL else { return }
        
        let currentModDate = modificationDate(of: url)
        
        // No change in modification date
        guard currentModDate != lastKnownFileModDate else { return }
        lastKnownFileModDate = currentModDate
        
        // File was modified externally — read new content
        guard let newContent = try? String(contentsOf: url, encoding: .utf8) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.onFileContentChanged?(newContent)
        }
    }
    
    // MARK: - Private: Vault Change Detection
    
    private func checkVaultForChanges() {
        guard let url = watchedVaultURL else { return }
        
        let currentHash = snapshotHash(of: url)
        
        guard currentHash != lastVaultSnapshotHash else { return }
        lastVaultSnapshotHash = currentHash
        
        DispatchQueue.main.async { [weak self] in
            self?.onVaultStructureChanged?()
        }
    }
    
    // MARK: - Private: Helpers
    
    private func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
    
    /// Creates a lightweight hash of the vault directory structure (file names + mod dates).
    /// Much cheaper than comparing full snapshots.
    private func snapshotHash(of directoryURL: URL) -> Int {
        let fm = FileManager.default
        var hasher = Hasher()
        
        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        while let fileURL = enumerator.nextObject() as? URL {
            let relativePath = fileURL.path.replacingOccurrences(of: directoryURL.path, with: "")
            hasher.combine(relativePath)
            
            if let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                hasher.combine(modDate)
            }
        }
        
        return hasher.finalize()
    }
}
