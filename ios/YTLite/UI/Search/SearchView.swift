import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [VideoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func submit() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            do {
                results = try await InnerTubeClient.searchVideos(query: q)
                if results.isEmpty {
                    errorMessage = "No videos found"
                }
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var playback: PlaybackController
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.results.isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text(viewModel.errorMessage ?? "Search videos and tap to play.")
                    )
                } else {
                    List {
                        ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                            Button {
                                playback.play(items: viewModel.results, startAt: index)
                                showPlayer = true
                            } label: {
                                VideoRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, prompt: "Search videos, channels…")
            .onSubmit(of: .search) { viewModel.submit() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Go") { viewModel.submit() }
                        .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showPlayer) {
                NavigationStack { PlayerDetailView() }
            }
        }
    }
}
