import SwiftUI

struct WebDAVBrowserSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sources = ImportSourceStore.shared

    @State private var showAdd = false
    @State private var browsing: ImportSourceStore.WebDAVAccount?
    @State private var pathStack: [String] = ["/"]
    @State private var entries: [WebDAVEntry] = []
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var statusMessage: String?
    @State private var statusClearTask: Task<Void, Never>?

    @State private var isSelectionMode = false
    @State private var selectedHrefs: Set<String> = []
    @State private var importedRemoteURIs: Set<String> = []

    private var fileEntries: [WebDAVEntry] {
        entries.filter { !$0.isCollection }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let account = browsing {
                    browserBody(account)
                } else {
                    accountList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ytLiteAppBackground()
            .navigationTitle(browsing?.displayName ?? L("import.source.webdav"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(YTLiteColor.background, for: .navigationBar)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showAdd) {
                WebDAVAccountEditor { showAdd = false }
            }
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
            if browsing != nil {
                if isSelectionMode {
                    toolbarIconButton("xmark", label: L("common.cancel")) {
                        exitSelectionMode()
                    }
                } else {
                    toolbarIconButton("chevron.left", label: L("import.nav.back")) {
                        navigateBack()
                    }
                }
            } else {
                toolbarIconButton("xmark", label: L("common.done")) {
                    dismiss()
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if let account = browsing {
                if isSelectionMode {
                    let importable = importableEntries(for: account)
                    toolbarIconButton("checklist", label: Lf("common.n_selected", importable.count)) {
                        selectedHrefs = Set(importable.map(\.href))
                    }
                    .disabled(importable.isEmpty)
                } else if !importableEntries(for: account).isEmpty {
                    toolbarIconButton("checkmark.circle", label: L("tab.import")) {
                        enterSelectionMode()
                    }
                }
            } else if !sources.webdavAccounts.isEmpty {
                toolbarIconButton("plus", label: L("import.webdav.add")) {
                    showAdd = true
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
        if browsing != nil, isSelectionMode, !selectedHrefs.isEmpty {
            Button {
                Task { await importSelected() }
            } label: {
                Text("\(L("tab.import")) · \(selectedHrefs.count)")
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(YTLiteColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
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
                .padding(.bottom, isSelectionMode && !selectedHrefs.isEmpty ? 72 : 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Accounts

    private var accountList: some View {
        Group {
            if sources.webdavAccounts.isEmpty {
                emptyAccountsState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sources.webdavAccounts) { account in
                            accountRow(account)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var emptyAccountsState: some View {
        ZStack {
            Color.clear
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(YTLiteColor.onAccent)
                    .frame(width: 72, height: 72)
                    .background(YTLiteColor.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("import.webdav.add"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func accountRow(_ account: ImportSourceStore.WebDAVAccount) -> some View {
        Button {
            browsing = account
            pathStack = [account.rootPath.isEmpty ? "/" : account.rootPath]
            errorText = nil
            statusMessage = nil
            exitSelectionMode()
            Task { await refreshList() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    YTLiteColor.surfaceVariant
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(YTLiteColor.accent)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))

                VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                    Text(account.displayName)
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    Text(account.baseURL)
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                sources.remove(accountId: account.id)
            } label: {
                Label(L("common.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Browser

    private func browserBody(_ account: ImportSourceStore.WebDAVAccount) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isSelectionMode {
                    Text(Lf("common.n_selected", selectedHrefs.count))
                        .font(YTLiteType.meta)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                if entries.isEmpty, !isBusy, errorText == nil {
                    Text(L("import.gdrive.empty"))
                        .font(YTLiteType.body)
                        .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .padding(.horizontal, YTLiteLayout.screenPadding)
                } else {
                    ForEach(entries) { entry in
                        entryRow(entry, account: account)
                    }
                }
            }
            .padding(.bottom, 88)
        }
    }

    private func entryRow(
        _ entry: WebDAVEntry,
        account: ImportSourceStore.WebDAVAccount
    ) -> some View {
        let selected = selectedHrefs.contains(entry.href)
        let alreadyImported = isAlreadyImported(entry, account: account)
        let selectionDisabled = entry.isCollection || alreadyImported
        return Button {
            if isSelectionMode {
                guard !selectionDisabled else { return }
                toggleSelection(entry.href)
            } else {
                Task { await open(entry, account: account) }
            }
        } label: {
            HStack(spacing: 14) {
                if isSelectionMode {
                    Image(systemName: selectionIcon(
                        entry: entry,
                        selected: selected,
                        alreadyImported: alreadyImported
                    ))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            selectionDisabled && !alreadyImported
                                ? YTLiteColor.onSurfaceVariant.opacity(0.35)
                                : (selected || alreadyImported
                                   ? YTLiteColor.accent
                                   : YTLiteColor.onSurfaceVariant)
                        )
                        .frame(width: 28)
                }

                ZStack {
                    YTLiteColor.surfaceVariant
                    Image(systemName: entry.isCollection ? "folder.fill" : "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(YTLiteColor.accent)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: YTLiteLayout.thumbRadius))

                VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                    Text(entry.displayName)
                        .font(YTLiteType.rowTitle)
                        .foregroundStyle(YTLiteColor.onSurface)
                        .lineLimit(1)
                    if let subtitle = entrySubtitle(entry) {
                        Text(subtitle)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !isSelectionMode {
                    trailingIcon(entry: entry, alreadyImported: alreadyImported)
                }
            }
            .padding(.horizontal, YTLiteLayout.screenPadding)
            .padding(.vertical, YTLiteLayout.rowVertical)
            .contentShape(Rectangle())
            .opacity(isSelectionMode && selectionDisabled && !alreadyImported ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSelectionMode && selectionDisabled)
    }

    @ViewBuilder
    private func trailingIcon(entry: WebDAVEntry, alreadyImported: Bool) -> some View {
        if entry.isCollection {
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        } else if alreadyImported {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(YTLiteColor.accent)
                .accessibilityLabel(L("import.filter.imported"))
        } else {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
        }
    }

    private func selectionIcon(
        entry: WebDAVEntry,
        selected: Bool,
        alreadyImported: Bool
    ) -> String {
        if entry.isCollection { return "folder.fill" }
        if alreadyImported { return "checkmark.circle.fill" }
        return selected ? "checkmark.circle.fill" : "circle"
    }

    private func entrySubtitle(_ entry: WebDAVEntry) -> String? {
        if entry.isCollection { return nil }
        guard let bytes = entry.contentLength, bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func navigateBack() {
        exitSelectionMode()
        clearTransientMessages()
        if pathStack.count > 1 {
            _ = pathStack.popLast()
            Task { await refreshList() }
            return
        }
        browsing = nil
        entries = []
        pathStack = ["/"]
    }

    private func enterSelectionMode() {
        selectedHrefs = []
        isSelectionMode = true
        clearTransientMessages()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedHrefs = []
    }

    private func toggleSelection(_ href: String) {
        if selectedHrefs.contains(href) {
            selectedHrefs.remove(href)
        } else {
            selectedHrefs.insert(href)
        }
    }

    private func importableEntries(
        for account: ImportSourceStore.WebDAVAccount
    ) -> [WebDAVEntry] {
        fileEntries.filter { !isAlreadyImported($0, account: account) }
    }

    private func remoteURI(
        for entry: WebDAVEntry,
        account: ImportSourceStore.WebDAVAccount
    ) -> String {
        "webdav:\(account.id):\(entry.href)"
    }

    private func isAlreadyImported(
        _ entry: WebDAVEntry,
        account: ImportSourceStore.WebDAVAccount
    ) -> Bool {
        let key = remoteURI(for: entry, account: account)
        if importedRemoteURIs.contains(key) { return true }
        let prefix = "webdav:\(account.id):"
        let decodedHref = entry.href.removingPercentEncoding ?? entry.href
        for uri in importedRemoteURIs where uri.hasPrefix(prefix) {
            let stored = String(uri.dropFirst(prefix.count))
            let storedDecoded = stored.removingPercentEncoding ?? stored
            if stored == entry.href || storedDecoded == decodedHref {
                return true
            }
        }
        return false
    }

    private func refreshImportedRemoteURIs() {
        importedRemoteURIs = Set(
            (store?.importedTracks() ?? [])
                .compactMap(\.remoteURI)
                .filter { $0.hasPrefix("webdav:") }
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

    // MARK: - Network

    private func refreshList() async {
        guard let account = browsing,
              let base = URL(string: account.baseURL),
              let password = sources.password(for: account.id)
        else { return }
        isBusy = true
        clearTransientMessages()
        defer { isBusy = false }
        do {
            let client = WebDAVClient(baseURL: base, username: account.username, password: password)
            let path = pathStack.last ?? "/"
            entries = try await client.list(path: path).filter { entry in
                entry.isCollection || ImportIngestService.isSupportedAudioURL(
                    URL(fileURLWithPath: entry.displayName)
                )
            }
            selectedHrefs = selectedHrefs.intersection(Set(fileEntries.map(\.href)))
            refreshImportedRemoteURIs()
        } catch {
            showError(error.localizedDescription)
            entries = []
        }
    }

    private func open(_ entry: WebDAVEntry, account: ImportSourceStore.WebDAVAccount) async {
        if entry.isCollection {
            pathStack.append(entry.href)
            exitSelectionMode()
            await refreshList()
            return
        }
        if isAlreadyImported(entry, account: account) {
            showStatus(L("import.filter.imported"))
            return
        }
        await importEntries([entry], account: account)
    }

    private func importSelected() async {
        guard let account = browsing else { return }
        let chosen = importableEntries(for: account).filter { selectedHrefs.contains($0.href) }
        guard !chosen.isEmpty else { return }
        await importEntries(chosen, account: account)
        exitSelectionMode()
    }

    private func importEntries(
        _ items: [WebDAVEntry],
        account: ImportSourceStore.WebDAVAccount
    ) async {
        guard let store,
              let base = URL(string: account.baseURL),
              let password = sources.password(for: account.id)
        else { return }
        guard await ImportNetworkGate.allowAutoCacheDownload() else {
            showError(L("import.settings.wifi_only_cache"))
            return
        }
        isBusy = true
        clearTransientMessages()
        defer { isBusy = false }

        let client = WebDAVClient(baseURL: base, username: account.username, password: password)
        var imported = 0
        var lastError: String?
        for entry in items {
            do {
                let data = try await client.download(path: entry.href)
                let ext = (entry.displayName as NSString).pathExtension
                _ = try await ImportIngestService.shared.ingestData(
                    data,
                    fileExtension: ext.isEmpty ? "mp3" : ext,
                    fileName: entry.displayName,
                    sourceKind: .webdav,
                    store: store,
                    remoteURI: remoteURI(for: entry, account: account),
                    cacheEligible: true
                )
                imported += 1
            } catch {
                lastError = error.localizedDescription
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

private struct WebDAVAccountEditor: View {
    var onDone: () -> Void
    @ObservedObject private var sources = ImportSourceStore.shared
    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var useNutstore = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: YTLiteLayout.screenPadding) {
                    Toggle(isOn: $useNutstore) {
                        Text(L("import.webdav.nutstore_preset"))
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurface)
                    }
                    .tint(YTLiteColor.accent)
                    .onChange(of: useNutstore) { _, on in
                        if on {
                            displayName = "Nutstore"
                            baseURL = "https://dav.jianguoyun.com/dav/"
                        }
                    }

                    editorField(L("import.webdav.display_name"), text: $displayName)
                    editorField(L("import.webdav.base_url"), text: $baseURL, urlStyle: true)
                    editorField(L("import.webdav.username"), text: $username, urlStyle: true)
                    VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
                        Text(L("import.webdav.password"))
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        SecureField("", text: $password)
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurface)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(YTLiteLayout.screenPadding)
            }
            .ytLiteAppBackground()
            .navigationTitle(L("import.webdav.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(YTLiteColor.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.save")) {
                        let account = ImportSourceStore.WebDAVAccount(
                            id: UUID().uuidString,
                            displayName: displayName.isEmpty ? "WebDAV" : displayName,
                            baseURL: baseURL,
                            username: username,
                            rootPath: "/",
                            preset: useNutstore ? "nutstore" : nil
                        )
                        sources.upsert(account, password: password)
                        onDone()
                    }
                    .font(YTLiteType.labelEmphasized)
                    .foregroundStyle(YTLiteColor.accent)
                    .disabled(baseURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(YTLiteColor.background)
    }

    private func editorField(
        _ title: String,
        text: Binding<String>,
        urlStyle: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: YTLiteLayout.stackTight) {
            Text(title)
                .font(YTLiteType.meta)
                .foregroundStyle(YTLiteColor.onSurfaceVariant)
            TextField("", text: text)
                .font(YTLiteType.body)
                .foregroundStyle(YTLiteColor.onSurface)
                .textInputAutocapitalization(urlStyle ? .never : .sentences)
                .autocorrectionDisabled(urlStyle)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(YTLiteColor.surfaceVariant, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
