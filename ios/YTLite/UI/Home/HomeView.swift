import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var videos: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                videos = try await InnerTubeClient.fetchHomeFeed()
                if videos.isEmpty {
                    errorMessage = "No videos in feed"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var playback: PlaybackController
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.videos.isEmpty {
                    ProgressView("Loading feed…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.videos.isEmpty {
                    ContentUnavailableView(
                        "Home",
                        systemImage: "house",
                        description: Text(viewModel.errorMessage ?? "Pull to refresh")
                    )
                } else {
                    List {
                        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, item in
                            Button {
                                playback.play(items: viewModel.videos, startAt: index)
                                showPlayer = true
                            } label: {
                                VideoRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { viewModel.load() }
                }
            }
            .navigationTitle("Home")
            .task {
                if viewModel.videos.isEmpty {
                    viewModel.load()
                }
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView() }
            }
        }
    }
}

struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
