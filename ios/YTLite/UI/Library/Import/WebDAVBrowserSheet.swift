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

    var body: some View {
        NavigationStack {
            Group {
                if let account = browsing {
                    browserList(account)
                } else {
                    accountList
                }
            }
            .ytLiteAppBackground()
            .navigationTitle(browsing?.displayName ?? L("import.source.webdav"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if browsing != nil {
                        Button(L("import.nav.back")) {
                            browsing = nil
                            entries = []
                            pathStack = ["/"]
                        }
                    } else {
                        Button(L("common.done")) { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if browsing == nil {
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                WebDAVAccountEditor { showAdd = false }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var accountList: some View {
        List {
            ForEach(sources.webdavAccounts) { account in
                Button {
                    browsing = account
                    pathStack = [account.rootPath.isEmpty ? "/" : account.rootPath]
                    Task { await refreshList() }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName)
                            .foregroundStyle(YTLiteColor.onSurface)
                        Text(account.baseURL)
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        sources.remove(accountId: account.id)
                    } label: {
                        Label(L("common.delete"), systemImage: "trash")
                    }
                }
            }
            if sources.webdavAccounts.isEmpty {
                Text(L("import.webdav.empty_accounts"))
                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func browserList(_ account: ImportSourceStore.WebDAVAccount) -> some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            ForEach(entries) { entry in
                Button {
                    Task { await open(entry, account: account) }
                } label: {
                    Label(
                        entry.displayName,
                        systemImage: entry.isCollection ? "folder" : "music.note"
                    )
                    .foregroundStyle(YTLiteColor.onSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay { if isBusy { ProgressView() } }
        .safeAreaInset(edge: .bottom) {
            if pathStack.count > 1 {
                Button(L("import.nav.back")) {
                    _ = pathStack.popLast()
                    Task { await refreshList() }
                }
                .padding()
            }
        }
    }

    private func refreshList() async {
        guard let account = browsing,
              let base = URL(string: account.baseURL),
              let password = sources.password(for: account.id)
        else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let client = WebDAVClient(baseURL: base, username: account.username, password: password)
            let path = pathStack.last ?? "/"
            entries = try await client.list(path: path).filter { entry in
                entry.isCollection || ImportIngestService.isSupportedAudioURL(
                    URL(fileURLWithPath: entry.displayName)
                )
            }
        } catch {
            errorText = error.localizedDescription
            entries = []
        }
    }

    private func open(_ entry: WebDAVEntry, account: ImportSourceStore.WebDAVAccount) async {
        if entry.isCollection {
            pathStack.append(entry.href)
            await refreshList()
            return
        }
        guard let store,
              let base = URL(string: account.baseURL),
              let password = sources.password(for: account.id)
        else { return }
        guard await ImportNetworkGate.allowAutoCacheDownload() else {
            errorText = L("import.settings.wifi_only_cache")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let client = WebDAVClient(baseURL: base, username: account.username, password: password)
            let data = try await client.download(path: entry.href)
            let ext = (entry.displayName as NSString).pathExtension
            _ = try await ImportIngestService.shared.ingestData(
                data,
                fileExtension: ext.isEmpty ? "mp3" : ext,
                fileName: entry.displayName,
                sourceKind: .webdav,
                store: store,
                remoteURI: "webdav:\(account.id):\(entry.href)",
                cacheEligible: true
            )
            onImported()
            errorText = Lf("import.status.imported_n", 1)
        } catch {
            errorText = error.localizedDescription
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
            Form {
                Toggle(L("import.webdav.nutstore_preset"), isOn: $useNutstore)
                    .onChange(of: useNutstore) { _, on in
                        if on {
                            displayName = "Nutstore"
                            baseURL = "https://dav.jianguoyun.com/dav/"
                        }
                    }
                TextField(L("import.webdav.display_name"), text: $displayName)
                TextField(L("import.webdav.base_url"), text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(L("import.webdav.username"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(L("import.webdav.password"), text: $password)
            }
            .navigationTitle(L("import.webdav.add"))
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
                    .disabled(baseURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
        }
    }
}
