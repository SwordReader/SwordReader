import BibleKit
import BibleUI
import SwiftUI

/// Opens an explicitly chosen, read-only BibleKit JSON feed.
struct ContentFeedBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var provider: BibleFeedProvider?
    @State private var contents: [BibleContentDescriptor] = []
    @State private var path: [BibleContentDescriptor] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if provider != nil {
                    BibleCatalogView(contents: contents) { path.append($0) }
                } else {
                    Form {
                        Section("Content Feed") {
                            TextField("HTTPS feed URL", text: $urlText)
                                .textContentType(.URL)
                            Text("Open a BibleKit JSON feed supplied by a publisher or custom source. Opening it contacts that server. Content stays in memory for this session; no publisher account or permanent download is created.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Open Feed") { openFeed() }
                                .disabled(isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if isLoading { ProgressView("Opening Feed…") }
                            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                        }
                    }
                }
            }
            .navigationTitle("Content Feeds")
            .navigationDestination(for: BibleContentDescriptor.self) { descriptor in
                if let provider { FeedEntriesView(provider: provider, descriptor: descriptor).environment(model) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 340, minHeight: 420)
        .onDisappear { loadTask?.cancel() }
    }

    private func openFeed() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else {
            errorMessage = "Enter a valid HTTPS feed URL."
            return
        }
        loadTask?.cancel()
        isLoading = true; errorMessage = nil
        loadTask = Task {
            defer { isLoading = false }
            do {
                let loaded = try await BibleFeedProvider.load(from: url)
                let catalog = try await loaded.catalog()
                try Task.checkCancellation()
                contents = catalog; provider = loaded
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct FeedEntriesView: View {
    @Environment(AppModel.self) private var model
    let provider: BibleFeedProvider
    let descriptor: BibleContentDescriptor
    @State private var locations: [BibleReadingLocation]?
    @State private var errorMessage: String?
    var body: some View {
        Group {
            if let locations {
                BibleEntryReader(provider: provider, descriptor: descriptor, locations: locations)
                    .font(.system(size: model.readerFontSize, design: model.readerFont.design))
            } else if let errorMessage {
                ContentUnavailableView("Unable to Open Content", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else { ProgressView() }
        }
        .task {
            do { locations = try await provider.locations(contentID: descriptor.contentID) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
