import Foundation
import AppKit

func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func directorySize(at path: String) -> (size: Int64, count: Int) {
    let fm = FileManager.default
    var totalSize: Int64 = 0
    var fileCount = 0

    guard let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: path),
        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles],
        errorHandler: { _, _ in true }
    ) else {
        return (0, 0)
    }

    for case let fileURL as URL in enumerator {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              resourceValues.isRegularFile == true,
              let size = resourceValues.fileSize else { continue }
        totalSize += Int64(size)
        fileCount += 1
    }

    return (totalSize, fileCount)
}

func openInFinder(path: String) {
    let url = URL(fileURLWithPath: path)
    if FileManager.default.fileExists(atPath: path) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
        // Try opening parent directory
        let parent = url.deletingLastPathComponent()
        NSWorkspace.shared.open(parent)
    }
}

func revealInFinder(path: String) {
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
}

func deleteContents(of path: String) throws -> Int {
    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(atPath: path)
    var deleted = 0
    for item in contents {
        let fullPath = (path as NSString).appendingPathComponent(item)
        try fm.removeItem(atPath: fullPath)
        deleted += 1
    }
    return deleted
}

func deleteFile(at path: String) throws {
    try FileManager.default.removeItem(atPath: path)
}
