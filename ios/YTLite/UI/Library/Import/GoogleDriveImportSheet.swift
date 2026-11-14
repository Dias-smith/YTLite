import SwiftUI

struct GoogleDriveImportSheet: View {
    var onImported: () -> Void

    @EnvironmentObject private var auth: AuthService
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
                        Task { await signInAndReload() }
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
                            client.signOut(auth: auth)
                            files = []
                        }
                    }
                }
            }
            .task {
                client.attach(auth: auth)
                await migrateLegacyDriveAuthIfNeeded()
                if client.isAuthorized {
                    await reload()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Legacy Keychain Drive token without Supabase Google session → one OAuth so Subs is signed in.
    private func migrateLegacyDriveAuthIfNeeded() async {
        client.syncAuthorizedFlag(auth: auth)
        let hasLegacy = ImportSourceStore.shared.token(provider: "gdrive") != nil
        let hasGoogleSession = auth.authProvider == .google && auth.googleAccessToken != nil
        guard hasLegacy, !hasGoogleSession else { return }
        _ = await auth.ensureGoogleDriveAccess(source: "import_gdrive_migrate")
        if let token = await auth.ensureFreshGoogleAccessToken() ?? auth.googleAccessToken {
            ImportSourceStore.shared.setToken(
                provider: "gdrive",
                accessToken: token,
                refreshToken: nil,
                expiry: Date().addingTimeInterval(3500)
            )
        }
        client.attach(auth: auth)
    }

    private func signInAndReload() async {
        isBusy = true
        defer { isBusy = false }
        await client.signIn(auth: auth)
        if client.isAuthorized {
            await reload()
        }
    }

    private func reload() async {
        isBusy = true
        defer { isBusy = false }
        do {
            files = try await client.listAudioFiles().files
            if !files.isEmpty || client.isAuthorized {
                auth.markGoogleDriveGranted()
            }
        } catch {
            message = error.localizedDescription
            if (error as? URLError)?.code == .userAuthenticationRequired {
                client.syncAuthorizedFlag(auth: auth)
            }
        }
    }

    private func importFile(_ file: GoogleDriveImportClient.DriveFile) async {
        guard let store else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await client.download(fileId: file.id)
            let ext = (file.name as NSString).pathExtension
            let useExt = ext.isEmpty ? "m4a" : ext
            _ = try await ImportIngestService.shared.ingestData(
                data,
                fileExtension: useExt,
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
