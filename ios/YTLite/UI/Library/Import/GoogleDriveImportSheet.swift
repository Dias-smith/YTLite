import SwiftUI

struct GoogleDriveImportSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var client = GoogleDriveImportClient.shared

    @State private var files: [GoogleDriveImportClient.DriveFile] = []
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                if !client.isAuthorized {
                    Button(L("import.gdrive.sign_in")) {
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
                            Task { await importFile(file) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .foregroundStyle(YTLiteColor.onSurface)
                                Text(file.mimeType)
                                    .font(YTLiteType.meta)
                                    .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            }
                        }
                    }
                    if files.isEmpty, !isBusy {
                        Text(L("import.gdrive.empty"))
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
            .navigationTitle(L("import.source.gdrive"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.done")) { dismiss() }
                }
                if client.isAuthorized {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L("import.gdrive.sign_out")) {
                            client.signOut()
                            files = []
                        }
                    }
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
            files = try await client.listAudioFiles().files
        } catch {
            message = error.localizedDescription
        }
    }

    private func importFile(_ file: GoogleDriveImportClient.DriveFile) async {
        guard let store else { return }
        guard await ImportNetworkGate.allowAutoCacheDownload() else {
            message = L("import.settings.wifi_only_cache")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.download(fileId: file.id)
            let ext = (file.name as NSString).pathExtension
            _ = try await ImportIngestService.shared.ingestData(
                data,
                fileExtension: ext.isEmpty ? "mp3" : ext,
                fileName: file.name,
                sourceKind: .gdrive,
                store: store,
                remoteURI: "gdrive:\(file.id)",
                cacheEligible: true
            )
            message = Lf("import.status.imported_n", 1)
            onImported()
        } catch {
            message = error.localizedDescription
        }
    }
}
