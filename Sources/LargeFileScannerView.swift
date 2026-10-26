import SwiftUI
import Foundation

struct LargeFile: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let size: Int64
    let modificationDate: Date
    var isDeleted: Bool = false
}

enum LargeFileSortColumn {
    case name, size, modified
}

class LargeFileScannerViewModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var directoriesScanned: Int = 0
    @Published var minSizeMB: Double = 100
    @Published var scanPath: String = ""
    @Published var error: String? = nil
    @Published var sortColumn: LargeFileSortColumn = .size
    @Published var sortAscending = false

    private var scanWorkItem: DispatchWorkItem?

    init() {
        scanPath = FileManager.default.homeDirectoryForCurrentUser.path
    }

    var minSizeOptions: [(String, Double)] {
        [
            ("50 MB", 50),
            ("100 MB", 100),
            ("250 MB", 250),
            ("500 MB", 500),
            ("1 GB", 1024),
            ("5 GB", 5120),
        ]
    }

    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        files = []
        error = nil
        directoriesScanned = 0
        scanProgress = "Starting scan..."

        let path = scanPath
        let minBytes = Int64(minSizeMB * 1_000_000)

        let workItem = DispatchWorkItem { [weak self] in
            let fm = FileManager.default

            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey, .isDirectoryKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                DispatchQueue.main.async {
                    self?.error = "Cannot access \(path)"
                    self?.isScanning = false
                }
                return
            }

            var foundFiles: [LargeFile] = []
            var dirCount = 0

            for case let fileURL as URL in enumerator {
                if (self?.scanWorkItem?.isCancelled ?? true) { break }

                guard let resourceValues = try? fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isRegularFileKey, .contentModificationDateKey, .isDirectoryKey]
                ) else { continue }

                if resourceValues.isDirectory == true {
                    dirCount += 1
                    if dirCount % 50 == 0 {
                        let currentDir = fileURL.lastPathComponent
                        let count = dirCount
                        DispatchQueue.main.async {
                            self?.directoriesScanned = count
                            self?.scanProgress = "Scanning: \(currentDir)"
                        }
                    }

                    // Skip certain system directories that are slow or inaccessible
                    let lastComponent = fileURL.lastPathComponent
                    if lastComponent == ".git" || lastComponent == "node_modules" ||
                       lastComponent == ".Spotlight-V100" || lastComponent == ".fseventsd" ||
                       lastComponent == "Photos Library.photoslibrary" {
                        enumerator.skipDescendants()
                        continue
                    }
                    continue
                }

                guard resourceValues.isRegularFile == true,
                      let size = resourceValues.fileSize,
                      Int64(size) >= minBytes else { continue }

                let modDate = resourceValues.contentModificationDate ?? Date.distantPast

                let file = LargeFile(
                    path: fileURL.path,
                    name: fileURL.lastPathComponent,
                    size: Int64(size),
                    modificationDate: modDate
                )
                foundFiles.append(file)

                // Update UI periodically
                if foundFiles.count % 5 == 0 {
                    let currentFiles = foundFiles
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.files = self.sorted(currentFiles)
                    }
                }
            }

            let wasCancelled = self?.scanWorkItem?.isCancelled ?? false
            let finalFiles = foundFiles
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.files = self.sorted(finalFiles)
                self.isScanning = false
                self.scanProgress = wasCancelled ? "Scan cancelled" : "Scan complete"
            }
        }

        scanWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func cancelScan() {
        scanWorkItem?.cancel()
        // Set a flag via the work item's isCancelled
        isScanning = false
        scanProgress = "Cancelling..."
        // Create a new cancelled item to replace
        scanWorkItem = nil
        scanProgress = "Scan cancelled"
    }

    func deleteFile(id: UUID) throws {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        try FileManager.default.removeItem(atPath: files[index].path)
        files[index].isDeleted = true
    }

    func sortBy(_ column: LargeFileSortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            // Names read best A-Z; sizes and dates read best largest/newest first
            sortAscending = column == .name
        }
        files = sorted(files)
    }

    private func sorted(_ list: [LargeFile]) -> [LargeFile] {
        let column = sortColumn
        let ascending = sortAscending
        func isAscending(_ a: LargeFile, _ b: LargeFile) -> Bool {
            switch column {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: return a.size < b.size
            case .modified: return a.modificationDate < b.modificationDate
            }
        }
        return list.sorted { ascending ? isAscending($0, $1) : isAscending($1, $0) }
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

    var totalFoundSize: Int64 {
        files.filter { !$0.isDeleted }.reduce(0) { $0 + $1.size }
    }
}

// MARK: - Views

struct LargeFileScannerView: View {
    @StateObject private var viewModel = LargeFileScannerViewModel()
    @State private var confirmDeleteID: UUID? = nil
    @State private var showConfirmDelete = false
    @State private var deleteError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text("Large File Scanner")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 16) {
                    // Scan path
                    HStack(spacing: 8) {
                        Text("Scan:")
                            .foregroundColor(.secondary)
                        Text(viewModel.scanPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .leading)
                        Button("Browse...") {
                            viewModel.chooseScanPath()
                        }
                        .controlSize(.small)
                    }

                    Divider().frame(height: 20)

                    // Min size
                    HStack(spacing: 8) {
                        Text("Min size:")
                            .foregroundColor(.secondary)
                        Picker("", selection: $viewModel.minSizeMB) {
                            ForEach(viewModel.minSizeOptions, id: \.1) { label, value in
                                Text(label).tag(value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    Spacer()

                    // Scan button
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
                        if viewModel.directoriesScanned > 0 {
                            Text("(\(viewModel.directoriesScanned) directories scanned)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !viewModel.files.isEmpty {
                            Text("\(viewModel.files.filter { !$0.isDeleted }.count) files found - \(formatSize(viewModel.totalFoundSize))")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                }

                if let error = viewModel.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.bottom, 12)

            // Results
            if viewModel.files.isEmpty && !viewModel.isScanning {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Click Scan to search for large files")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                // Table header
                HStack(spacing: 0) {
                    sortHeader("Name", .name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader("Size", .size)
                        .frame(width: 100, alignment: .trailing)
                    sortHeader("Modified", .modified)
                        .frame(width: 110, alignment: .trailing)
                    Text("Actions")
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .center)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.files) { file in
                            LargeFileRow(
                                file: file,
                                onReveal: { openInFinder(path: file.path) },
                                onDelete: {
                                    confirmDeleteID = file.id
                                    showConfirmDelete = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .alert("Delete File?", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    do {
                        try viewModel.deleteFile(id: id)
                        deleteError = nil
                    } catch {
                        deleteError = error.localizedDescription
                    }
                }
            }
        } message: {
            if let file = viewModel.files.first(where: { $0.id == confirmDeleteID }) {
                Text("Permanently delete \"\(file.name)\"?\n\nSize: \(formatSize(file.size))\nPath: \(file.path)\n\nThis action cannot be undone.")
            }
        }
        .alert("Delete Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            if let err = deleteError {
                Text(err)
            }
        }
    }

    private func sortHeader(_ title: String, _ column: LargeFileSortColumn) -> some View {
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
}

struct LargeFileRow: View {
    let file: LargeFile
    let onReveal: () -> Void
    let onDelete: () -> Void

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }

    var body: some View {
        HStack(spacing: 0) {
            // Name + path
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(.body))
                    .strikethrough(file.isDeleted)
                    .foregroundColor(file.isDeleted ? .secondary : .primary)
                    .lineLimit(1)
                Text(file.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(formatSize(file.size))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(
                    file.isDeleted ? .secondary :
                    file.size > 5_000_000_000 ? .red :
                    file.size > 1_000_000_000 ? .orange : .primary
                )
                .frame(width: 100, alignment: .trailing)

            // Date
            Text(dateFormatter.string(from: file.modificationDate))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)

            // Actions
            HStack(spacing: 4) {
                Button(action: onReveal) {
                    Image(systemName: "folder")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .disabled(file.isDeleted)
                .help("Reveal in Finder")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 26)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .disabled(file.isDeleted)
                .help("Delete file")
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(file.isDeleted ? Color(nsColor: .controlBackgroundColor).opacity(0.5) : Color.clear)
        )
    }
}
