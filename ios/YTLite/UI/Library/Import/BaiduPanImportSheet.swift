import SwiftUI

struct BaiduPanImportSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var client = BaiduPanImportClient.shared

    @State private var pathStack: [String] = ["/"]
    @State private var files: [BaiduPanImportClient.PanFile] = []
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if !client.isAuthorized {
                    Button(L("import.baidu.sign_in")) {
                        Task {
                            await client.signIn()
                            if client.isAuthorized {
                                await reload()
                            }
                        }
                    }
                } else {
                    ForEach(files) { file in
                        Button {
                            Task { await open(file) }
                        } label: {
                            Label(
                                file.name,
                                systemImage: file.isDir ? "folder" : "music.note"
                            )
                            .foregroundStyle(YTLiteColor.onSurface)
                        }
                    }
                    if files.isEmpty, !isBusy {
                        Text(L("import.baidu.empty"))
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                    }
                }
                if let err = client.lastError ?? message {
                    Text(err).foregroundStyle(.red)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay { if isBusy { ProgressView() } }
            .ytLiteAppBackground()
            .navigationTitle(L("import.source.baidu"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.done")) { dismiss() }
                }
                if client.isAuthorized {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L("import.baidu.sign_out")) {
                            client.signOut()
                            files = []
                            pathStack = ["/"]
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if pathStack.count > 1 {
                    Button(L("import.nav.back")) {
                        _ = pathStack.popLast()
                        Task { await reload() }
                    }
                    .padding()
                }
            }
            .task {
                if client.isAuthorized {
                    await reload()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func reload() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let path = pathStack.last ?? "/"
            files = try await client.list(path: path).filter { file in
                file.isDir || LocalMediaStore.audioExtensions.contains(
                    (file.name as NSString).pathExtension.lowercased()
                )
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func open(_ file: BaiduPanImportClient.PanFile) async {
        if file.isDir {
            pathStack.append(file.path)
            await reload()
            return
        }
        guard let store else { return }
        guard await ImportNetworkGate.allowAutoCacheDownload() else {
            message = L("import.settings.wifi_only_cache")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.download(fsId: file.id)
            let ext = (file.name as NSString).pathExtension
            _ = try await ImportIngestService.shared.ingestData(
                data,
                fileExtension: ext.isEmpty ? "mp3" : ext,
                fileName: file.name,
                sourceKind: .baidu,
                store: store,
                remoteURI: "baidu:\(file.id)",
                cacheEligible: true
            )
            message = Lf("import.status.imported_n", 1)
            onImported()
        } catch {
            message = error.localizedDescription
        }
    }
}
