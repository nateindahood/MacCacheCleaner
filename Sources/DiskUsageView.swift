import SwiftUI
import Foundation
import AppKit

final class FileNode: Identifiable {
    let name: String
    let isDirectory: Bool
    let modificationDate: Date
    var size: Int64 = 0
    var fileCount: Int = 0
    var children: [FileNode] = []
    weak var parent: FileNode?
    private let rootPath: String?

    init(name: String, isDirectory: Bool, modificationDate: Date, parent: FileNode?, rootPath: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.modificationDate = modificationDate
        self.parent = parent
        self.rootPath = rootPath
    }

    // Paths are rebuilt from the parent chain so each node doesn't store a full path
    var path: String {
        if let rootPath = rootPath { return rootPath }
        return ((parent?.path ?? "") as NSString).appendingPathComponent(name)
    }

    // nil hides the disclosure triangle for files and empty folders
    var visibleChildren: [FileNode]? {
        children.isEmpty ? nil : children
    }

    var fractionOfParent: Double {
        guard let parent = parent, parent.size > 0 else { return 1 }
        return Double(size) / Double(parent.size)
    }
}

enum DiskUsageSortColumn {
    case name, size, items, modified
}

private final class ScanToken {
    var isCancelled = false
}

class DiskUsageViewModel: ObservableObject {
    @Published var root: FileNode? = nil
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var filesScanned: Int = 0
    @Published var scanPath: String = ""
    @Published var error: String? = nil
    @Published var sortColumn: DiskUsageSortColumn = .size
    @Published var sortAscending = false
    @Published var includeICloud = false

    private var scanToken: ScanToken?

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey,
    ]

    init() {
        scanPath = FileManager.default.homeDirectoryForCurrentUser.path
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        root = nil
        error = nil
        filesScanned = 0
        scanProgress = "Starting scan..."

        let path = scanPath
        let token = ScanToken()
        scanToken = token
        let column = sortColumn
        let ascending = sortAscending
        // iCloud Drive files may be cloud-only placeholders, which are slow to enumerate
        let excludedPaths: Set<String> = includeICloud ? [] : [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents").standardizedFileURL.path
        ]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = URL(fileURLWithPath: path)
            let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let rootNode = FileNode(name: url.lastPathComponent, isDirectory: true,
                                    modificationDate: modDate ?? .distantPast, parent: nil, rootPath: path)
            var fileCount = 0
            self?.scanDirectory(rootNode, url: url, token: token, excludedPaths: excludedPaths, fileCount: &fileCount)
            DiskUsageViewModel.sortTree(rootNode, by: column, ascending: ascending)

            DispatchQueue.main.async {
                guard let self = self, self.scanToken === token else { return }
                self.root = rootNode
                self.filesScanned = fileCount
                self.isScanning = false
                self.scanProgress = token.isCancelled ? "Scan cancelled (partial results)" : "Scan complete"
                self.scanToken = nil
            }
        }
    }

    private func scanDirectory(_ node: FileNode, url: URL, token: ScanToken,
                               excludedPaths: Set<String>, fileCount: inout Int) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Self.resourceKeys, options: []
        ) else { return }

        for itemURL in contents {
            if token.isCancelled { return }
            guard let values = try? itemURL.resourceValues(forKeys: Set(Self.resourceKeys)) else { continue }

            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            let child = FileNode(name: itemURL.lastPathComponent, isDirectory: isDirectory,
                                 modificationDate: values.contentModificationDate ?? .distantPast, parent: node)

            if isDirectory {
                // Don't cross into other mounted volumes (e.g. /Volumes/*, /System/Volumes/Data)
                if excludedPaths.contains(itemURL.standardizedFileURL.path) {
                    continue
                }
                if values.isVolume != true {
                    scanDirectory(child, url: itemURL, token: token, excludedPaths: excludedPaths, fileCount: &fileCount)
                }
            } else {
                child.size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                child.fileCount = 1
                fileCount += 1
                if fileCount % 500 == 0 {
                    let count = fileCount
                    let currentDir = url.lastPathComponent
                    DispatchQueue.main.async { [weak self] in
                        guard self?.scanToken === token else { return }
                        self?.filesScanned = count
                        self?.scanProgress = "Scanning: \(currentDir)"
                    }
                }
            }

            node.size += child.size
            node.fileCount += child.fileCount
            node.children.append(child)
        }
    }

    func cancelScan() {
        scanToken?.isCancelled = true
        scanProgress = "Cancelling..."
    }

    func chooseScanPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Folder to Scan"
        panel.directoryURL = URL(fileURLWithPath: scanPath)

        if panel.runModal() == .OK, let url = panel.url {
            scanPath = url.path
        }
    }

    func sortBy(_ column: DiskUsageSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            // Names read best A-Z; numbers and dates read best largest/newest first
            sortAscending = column == .name
        }
        if let root = root {
            Self.sortTree(root, by: sortColumn, ascending: sortAscending)
            objectWillChange.send()
        }
    }

    private static func sortTree(_ node: FileNode, by column: DiskUsageSortColumn, ascending: Bool) {
        func isAscending(_ a: FileNode, _ b: FileNode) -> Bool {
            switch column {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: return a.size < b.size
            case .items: return a.fileCount < b.fileCount
            case .modified: return a.modificationDate < b.modificationDate
            }
        }
        node.children.sort { ascending ? isAscending($0, $1) : isAscending($1, $0) }
        for child in node.children where !child.children.isEmpty {
            sortTree(child, by: column, ascending: ascending)
        }
    }

    func remove(_ node: FileNode, permanently: Bool) {
        let url = URL(fileURLWithPath: node.path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                DispatchQueue.main.async { self?.detach(node) }
            } catch {
                DispatchQueue.main.async { self?.error = error.localizedDescription }
            }
        }
    }

    // Removes a deleted node from the tree and subtracts its totals from every ancestor
    private func detach(_ node: FileNode) {
        guard let parent = node.parent else { return }
        parent.children.removeAll { $0 === node }
        var ancestor: FileNode? = parent
        while let current = ancestor {
            current.size -= node.size
            current.fileCount -= node.fileCount
            ancestor = current.parent
        }
        objectWillChange.send()
    }
}

// MARK: - Views

struct DiskUsageView: View {
    @StateObject private var viewModel = DiskUsageViewModel()
    @State private var confirmDeleteNode: FileNode? = nil
    @State private var showConfirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Disk Usage")
                        .font(.title2)
                        .fontWeight(.semibold)
                    if let root = viewModel.root {
                        Text("\(formatSize(root.size)) in \(root.fileCount) files")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Text("Scan:")
                            .foregroundColor(.secondary)
                        Text(viewModel.scanPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 400, alignment: .leading)
                        Button("Browse...") {
                            viewModel.chooseScanPath()
                        }
                        .controlSize(.small)
                        .disabled(viewModel.isScanning)
                    }

                    Divider().frame(height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Include iCloud Drive", isOn: $viewModel.includeICloud)
                            .toggleStyle(.checkbox)
                            .disabled(viewModel.isScanning)
                        if viewModel.includeICloud {
                            Text("May add significant time to the scan")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Spacer()

                    if viewModel.isScanning {
                        Button(action: { viewModel.cancelScan() }) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .tint(.red)
                    } else {
                        Button(action: { viewModel.startScan() }) {
                            Label("Scan", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                // Progress
                if viewModel.isScanning || !viewModel.scanProgress.isEmpty {
                    HStack(spacing: 8) {
                        if viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.scanProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if viewModel.filesScanned > 0 {
                            Text("(\(viewModel.filesScanned) files scanned)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.bottom, 12)

            // Results
            if let root = viewModel.root {
                List {
                    Section(header: columnHeader) {
                        OutlineGroup(root.visibleChildren ?? [], children: \.visibleChildren) { node in
                            DiskUsageRow(node: node, size: node.size, fileCount: node.fileCount,
                                         fraction: node.fractionOfParent)
                                .contextMenu { contextMenu(for: node) }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(viewModel.isScanning ? "Scanning..." : "Click Scan to map folder sizes")
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .alert("Delete Permanently?", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let node = confirmDeleteNode {
                    viewModel.remove(node, permanently: true)
                }
            }
        } message: {
            if let node = confirmDeleteNode {
                Text("Permanently delete \"\(node.name)\"\(node.isDirectory ? " and everything inside it" : "")?\n\nSize: \(formatSize(node.size))\nPath: \(node.path)\n\nThis skips the Trash and cannot be undone.")
            }
        }
        .alert("Delete Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let err = viewModel.error {
                Text(err)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            sortHeader("Name", .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortHeader("Size", .size)
                .frame(width: 90, alignment: .trailing)
            Text("% of Parent")
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .center)
            sortHeader("Files", .items)
                .frame(width: 70, alignment: .trailing)
            sortHeader("Modified", .modified)
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption)
        .fontWeight(.semibold)
    }

    private func sortHeader(_ title: String, _ column: DiskUsageSortColumn) -> some View {
        let isActive = viewModel.sortColumn == column
        return Button(action: { viewModel.sortBy(column) }) {
            HStack(spacing: 3) {
                Text(title)
                if isActive {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(isActive ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }

    @ViewBuilder
    private func contextMenu(for node: FileNode) -> some View {
        Button("Reveal in Finder") {
            openInFinder(path: node.path)
        }
        Button("Open") {
            NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }
        Divider()
        Button("Move to Trash") {
            viewModel.remove(node, permanently: false)
        }
        Button("Delete Permanently...") {
            confirmDeleteNode = node
            showConfirmDelete = true
        }
    }
}

struct DiskUsageRow: View {
    let node: FileNode
    // Passed separately so rows refresh when totals change after a delete
    let size: Int64
    let fileCount: Int
    let fraction: Double

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            // Name
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                    .frame(width: 16)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(formatSize(size))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(size > 5_000_000_000 ? .red :
                                    size > 1_000_000_000 ? .orange : .primary)
                .frame(width: 90, alignment: .trailing)

            // % of parent
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(nsColor: .separatorColor).opacity(0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.1f%%", fraction * 100))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 130)
            .padding(.leading, 12)

            // File count
            Text(node.isDirectory ? "\(fileCount)" : "")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            // Date
            Text(Self.dateFormatter.string(from: node.modificationDate))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}
