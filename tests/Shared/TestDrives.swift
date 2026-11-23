// Drives for a test, on folders of its own (ExternalDrive.source): what a test sees can't depend on what is plugged into the
// Mac it runs on, nor on a disk image another series mounted meanwhile (23.11.2026). Compiled into the tests that look at
// drives: swiftc … tests/Shared/TestDrives.swift tests/<Test>/main.swift
import Foundation

enum TestDrives {
    /// No drive at all: what a Mac without one plugged in shows – the same on every Mac.
    static func none() { ExternalDrive.source = { [] } }

    /// Three drives in `root`, each a folder under root/Volumes: "Games" with Nightforge's folder on it (APFS, games go
    /// there), "Stick" from another Mac with Nightforge's folder too but FAT32 (nothing goes there), and "Empty" without
    /// Nightforge's folder (exFAT). From here on they are the drives plugged in.
    @discardableResult
    static func three(in root: URL, free: Int64 = 500 << 30) -> (games: ExternalDrive, stick: ExternalDrive, empty: ExternalDrive) {
        func drive(_ name: String, format: String, library: Bool) -> ExternalDrive {
            let url = root.appendingPathComponent("Volumes/\(name)", isDirectory: true)
            try? FileManager.default.createDirectory(at: library ? DriveLibrary.root(on: url) : url, withIntermediateDirectories: true)
            return ExternalDrive(name: name, url: url, format: format, readOnly: false, free: free, total: free * 2)
        }
        let drives = (games: drive("Games", format: "apfs", library: true), stick: drive("Stick", format: "msdos", library: true),
                      empty: drive("Empty", format: "exfat", library: false))
        ExternalDrive.source = { [drives.games, drives.stick, drives.empty] }
        return drives
    }
}
