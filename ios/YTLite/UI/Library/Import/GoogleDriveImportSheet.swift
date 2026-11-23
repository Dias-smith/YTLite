import SwiftUI

struct GoogleDriveImportSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var client = GoogleDriveImportClient.shared

    @State private var files: [GoogleDriveImportClient.DriveFile] = []
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var statusMessage: String?
    @State private var statusClearTask: Task<Void, Never>?

    @State private var isSelectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var importedRemoteURIs: Set<String> = []
    /// Byte fraction for each song currently downloading, shown on that row.
    @State private var rowProgress: [String: Double] = [:]

    private var importableFiles: [GoogleDriveImportClient.DriveFile] {
        files.filter { !isAlreadyImported($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    emptyBody
                } else {
                    fileList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ytLiteAppBackground()
            .navigationTitle(L("import.source.gdrive"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(YTLiteColor.background, for: .navigationBar)
            .toolbar { toolbarContent }
            .overlay {
                if isBusy {
                    ProgressView()
                        .padding(20)
                        .background(YTLiteColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(alignment: .bottom) {
                toastOverlay
            }
            .safeAreaInset(edge: .bottom) {
                bottomInset
            }
            .onAppear { refreshImportedRemoteURIs() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if isSelectionMode {
                toolbarIconButton("xmark", label: L("common.cancel")) {
                    exitSelectionMode()
                }
            } else {
                toolbarIconButton("xmark", label: L("common.done")) {
                    dismiss()
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if isSelectionMode {
                toolbarIconButton("checklist", label: Lf("common.n_selected", importableFiles.count)) {
                    selectedIds = Set(importableFiles.map(\.id))
                }
                .disabled(importableFiles.isEmpty)
            } else {
                toolbarIconButton("plus", label: L("import.gdrive.pick")) {
                    Task { await pickAndMerge() }
                }
                .disabled(isBusy || !rowProgress.isEmpty)
                if !importableFiles.isEmpty {
                    toolbarIconButton("checkmark.circle", label: L("tab.import")) {
                        enterSelectionMode()
                    }
                }
                if client.isAuthorized {
                    toolbarIconButton(
                        "rectangle.portrait.and.arrow.right",
                        label: L("import.gdrive.sign_out")
                    ) {
                        signOut()
                    }
                }
            }
        }
    }

    private func toolbarIconButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var bottomInset: some View {
        if isSelectionMode, !selectedIds.isEmpty {
            Button {
                Task { await importSelected() }
            } label: {
                Text("\(L("import.gdrive.download")) · \(selectedIds.count)")
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !rowProgress.isEmpty)
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let text = errorText ?? statusMessage {
            Text(text)
                .font(YTLiteType.meta)
                .foregroundStyle(
                    errorText != nil ? YTLiteColor.danger : YTLiteColor.onSurface
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(YTLiteColor.surfaceElevated, in: Capsule())
                .padding(.horizontal, YTLiteLayout.screenPadding)
                .padding(.bottom, isSelectionMode && !selectedIds.isEmpty ? 72 : 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var emptyBody: some View {
        VStack(spacing: YTLiteLayout.stackLoose) {
            Text(L("import.gdrive.empty"))
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, YTLiteLayout.screenPadding)

            Button {
                Task { await pickAndMerge() }
            } label: {
                Text(L("import.gdrive.pick"))
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isSelectionMode {
                    Text(Lf("common.n_selected", selectedIds.count))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                ForEach(files) { file in
                    fileRow(file)
                }
            }
            .padding(.bottom, 88)
        }
    }

    private func fileRow(_ file: GoogleDriveImportClient.DriveFile) -> some View {
        let selected = selectedIds.contains(file.id)
        let alreadyImported = isAlreadyImported(file)
        return Button {
            if isSelectionMode {
                guard !alreadyImported else { return }
                toggleSelection(file.id)
            } else {
                Task { await open(file) }
            }
        } label: {
            HStack(spacing: 14) {
                if isSelectionMode {
                    Image(systemName: selectionIcon(selected: selected, alreadyImported: alreadyImported))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            selected || alreadyImported
                                ? YTLiteColor.accent
                                : YTLiteColor.onSurfaceVariant
                        )
                        .frame(width: 28)
                }

                ZStack {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(YTLiteColor.accent)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))

                VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                    Text(file.name)
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    if let subtitle = fileSubtitle(file) {
                        Text(subtitle)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    if let fraction = rowProgress[file.id] {
                        songProgressBar(fraction)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                if !isSelectionMode {
                    Image(systemName: alreadyImported ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: alreadyImported ? 18 : 15, weight: .semibold))
                        .foregroundStyle(alreadyImported ? YTLiteColor.accent : YTLiteColor.onSurfaceVariant)
                        .accessibilityLabel(alreadyImported ? L("import.filter.imported") : L("import.gdrive.download"))
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled((isSelectionMode && alreadyImported) || !rowProgress.isEmpty)
    }

    private func songProgressBar(_ fraction: Double) -> some View {
        let clamped = CGFloat(min(1, max(0, fraction)))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(YTLiteColor.surfaceVariant)
                Capsule()
                    .fill(YTLiteColor.accent)
                    .frame(width: max(0, geo.size.width * clamped))
            }
        }
        .frame(height: 4)
        .padding(.top, 2)
        .accessibilityLabel(L("import.gdrive.download"))
    }

    private func setRowProgress(_ id: String, _ fraction: Double) {
        guard let current = rowProgress[id], current < 1, fraction >= current else { return }
        rowProgress[id] = fraction
    }

    private func selectionIcon(selected: Bool, alreadyImported: Bool) -> String {
        if alreadyImported || selected { return "checkmark.circle.fill" }
        return "circle"
    }

    private func fileSubtitle(_ file: GoogleDriveImportClient.DriveFile) -> String? {
        guard let bytes = file.size, bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func enterSelectionMode() {
        selectedIds = []
        isSelectionMode = true
        clearTransientMessages()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds = []
    }

    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func remoteURI(for file: GoogleDriveImportClient.DriveFile) -> String {
        "gdrive:\(file.id)"
    }

    private func isAlreadyImported(_ file: GoogleDriveImportClient.DriveFile) -> Bool {
        importedRemoteURIs.contains(remoteURI(for: file))
    }

    private func refreshImportedRemoteURIs() {
        importedRemoteURIs = Set(
            (store?.importedTracks() ?? [])
                .compactMap(\.remoteURI)
                .filter { $0.hasPrefix("gdrive:") }
        )
    }

    private func showStatus(_ text: String) {
        statusClearTask?.cancel()
        errorText = nil
        statusMessage = text
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }

    private func showError(_ text: String) {
        statusClearTask?.cancel()
        statusMessage = nil
        errorText = text
    }

    private func clearTransientMessages() {
        statusClearTask?.cancel()
        statusMessage = nil
        errorText = nil
    }

    private func signOut() {
        client.signOut()
        files = []
        exitSelectionMode()
        clearTransientMessages()
    }

    private func pickAndMerge() async {
        isBusy = true
        clearTransientMessages()
        defer { isBusy = false }
        let picked = await client.pickFiles()
        if let err = client.lastError {
            showError(err)
            return
        }
        guard !picked.isEmpty else { return }
        var seen = Set(files.map(\.id))
        var merged = files
        for file in picked where seen.insert(file.id).inserted {
            merged.append(file)
        }
        files = merged
        refreshImportedRemoteURIs()
    }

    private func open(_ file: GoogleDriveImportClient.DriveFile) async {
        if isAlreadyImported(file) {
            showStatus(L("import.filter.imported"))
            return
        }
        await importFiles([file])
    }

    private func importSelected() async {
        let chosen = importableFiles.filter { selectedIds.contains($0.id) }
        guard !chosen.isEmpty else { return }
        await importFiles(chosen)
        exitSelectionMode()
    }

    private func importFiles(_ items: [GoogleDriveImportClient.DriveFile]) async {
        guard let store, !items.isEmpty else { return }
        guard await ImportNetworkGate.allowAutoCacheDownload() else {
            showError(L("import.settings.wifi_only_cache"))
            return
        }
        rowProgress = Dictionary(uniqueKeysWithValues: items.map { ($0.id, 0) })
        clearTransientMessages()
        defer { rowProgress = [:] }

        var imported = 0
        var lastError: String?
        for file in items {
            let fileId = file.id
            do {
                let data = try await client.download(fileId: fileId, expectedBytes: file.size) { fraction in
                    Task { @MainActor in
                        self.setRowProgress(fileId, fraction)
                    }
                }
                let ext = (file.name as NSString).pathExtension
                let useExt = ext.isEmpty ? "m4a" : ext
                _ = try await ImportIngestService.shared.ingestData(
                    data,
                    fileExtension: useExt,
                    fileName: file.name,
                    sourceKind: .gdrive,
                    store: store,
                    remoteURI: remoteURI(for: file),
                    cacheEligible: true
                )
                rowProgress[fileId] = 1
                imported += 1
            } catch {
                rowProgress[fileId] = nil
                lastError = error.localizedDescription
                if (error as? URLError)?.code == .userAuthenticationRequired {
                    break
                }
            }
        }

        refreshImportedRemoteURIs()
        if imported > 0 {
            onImported()
            showStatus(Lf("import.status.imported_n", imported))
        }
        if let lastError {
            if imported > 0 {
                showError("\(Lf("import.status.imported_n", imported)) · \(lastError)")
            } else {
                showError(lastError)
            }
        }
    }
}
