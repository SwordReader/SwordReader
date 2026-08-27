import SwiftUI

struct StudyItemsView: View {
    @Environment(AppModel.self) private var model

    private var items: [StudyItem] {
        model.studyItems.filter { $0.kind == .note || $0.kind == .highlight }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Notes or Highlights",
                    systemImage: "highlighter",
                    description: Text("Select text in the reader, then right-click to highlight it or add a note.")
                )
            } else {
                List(items) { item in
                    Button {
                        model.section = .read
                        Task {
                            await model.open(destination: ReaderDestination(
                                moduleID: item.moduleID,
                                reference: item.reference
                            ))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(
                                item.reference,
                                systemImage: item.kind == .note ? "note.text" : "highlighter"
                            )
                            .font(.headline)
                            if let text = item.text {
                                Text(text)
                                    .lineLimit(3)
                                    .foregroundStyle(.secondary)
                            }
                            Text(moduleTitle(for: item.moduleID))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Notes & Highlights")
    }

    private func moduleTitle(for moduleID: String) -> String {
        model.modules.first { $0.id == moduleID }?.title
            ?? model.keyedModules.first { $0.id == moduleID }?.title
            ?? moduleID
    }
}
