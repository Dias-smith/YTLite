import CoreImage.CIFilterBuiltins
import SwiftUI

struct WiFiImportSheet: View {
    var onImported: () -> Void

    @Environment(\.libraryStore) private var store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var server = WiFiImportServer.shared
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        Text(L("import.wifi.hint"))
                            .font(YTLiteType.body)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if server.isRunning {
                            Text(L("import.wifi.running"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.accent)
                        }

                        if let url = server.listenURL {
                            Text(url.absoluteString)
                                .font(YTLiteType.sectionTitle)
                                .foregroundStyle(YTLiteColor.onSurface)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button(L("import.wifi.copy")) {
                                        UIPasteboard.general.string = url.absoluteString
                                    }
                                }
                            if let qr = qrImage(for: url.absoluteString) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .padding()
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            }
                            Button(L("import.wifi.copy")) {
                                UIPasteboard.general.string = url.absoluteString
                            }
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.accent)
                        } else if let err = server.lastError {
                            Text(err)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button(L("import.wifi.retry")) {
                                server.start()
                            }
                            .font(YTLiteType.labelEmphasized)
                            .foregroundStyle(YTLiteColor.accent)
                        } else if server.isRunning {
                            ProgressView()
                            Text(L("import.wifi.waiting_ip"))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }

                        Text(Lf("import.wifi.imported_count", server.importedCount))
                            .font(YTLiteType.meta)
                            .foregroundStyle(YTLiteColor.onSurfaceVariant)

                        if server.failedCount > 0 {
                            Text(Lf("import.wifi.failed_count", server.failedCount))
                                .font(YTLiteType.meta)
                                .foregroundStyle(YTLiteColor.onSurfaceVariant)
                        }

                        if let message {
                            Text(message)
                                .font(YTLiteType.meta)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }

                YTLiteSheetPrimaryButton(title: L("import.wifi.close_stop")) {
                    closeAndStop()
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .ytLiteAppBackground()
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(L("import.source.wifi"))
                    .font(YTLiteType.sectionTitle)
                    .foregroundStyle(YTLiteColor.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .interactiveDismissDisabled(true)
            .onAppear {
                message = nil
                server.onFileReceived = { data, filename in
                    guard let store else { return false }
                    let ext = (filename as NSString).pathExtension
                    do {
                        _ = try await ImportIngestService.shared.ingestData(
                            data,
                            fileExtension: ext.isEmpty ? "mp3" : ext,
                            fileName: filename,
                            sourceKind: .wifi,
                            store: store
                        )
                        message = nil
                        onImported()
                        return true
                    } catch {
                        message = error.localizedDescription
                        return false
                    }
                }
                server.start()
            }
            .onDisappear {
                server.stop()
                server.onFileReceived = nil
            }
        }
    }

    private func closeAndStop() {
        server.stop()
        server.onFileReceived = nil
        dismiss()
    }

    private func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
