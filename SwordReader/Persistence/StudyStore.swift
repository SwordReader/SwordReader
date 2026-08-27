import Foundation
import SwiftData

@MainActor
protocol StudyDataServing: AnyObject {
    func fetchAll() throws -> [StudyItem]
    func toggleBookmark(moduleID: String, reference: String) throws
    func saveNote(_ text: String?, moduleID: String, reference: String) throws
    func saveHighlight(_ text: String?, moduleID: String, reference: String) throws
}

enum StudyDataSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StudyRecord.self] }

    @Model
    final class StudyRecord {
        @Attribute(.unique) var id: String
        var kind: String
        var moduleID: String
        var reference: String
        var text: String?
        var createdAt: Date

        init(
            id: String,
            kind: String,
            moduleID: String,
            reference: String,
            text: String?,
            createdAt: Date = .now
        ) {
            self.id = id
            self.kind = kind
            self.moduleID = moduleID
            self.reference = reference
            self.text = text
            self.createdAt = createdAt
        }
    }
}

enum StudyDataMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StudyDataSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
final class StudyStore: StudyDataServing {
    private typealias Record = StudyDataSchemaV1.StudyRecord
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(
            for: StudyDataSchemaV1.StudyRecord.self,
            migrationPlan: StudyDataMigrationPlan.self,
            configurations: configuration
        )
    }

    func fetchAll() throws -> [StudyItem] {
        let records = try context.fetch(
            FetchDescriptor<Record>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        return records.compactMap(Self.item)
    }

    func toggleBookmark(moduleID: String, reference: String) throws {
        let id = Self.id(kind: .bookmark, moduleID: moduleID, reference: reference)
        if let existing = try record(id: id) {
            context.delete(existing)
        } else {
            context.insert(
                Record(
                    id: id,
                    kind: StudyItem.Kind.bookmark.rawValue,
                    moduleID: moduleID,
                    reference: reference,
                    text: nil
                )
            )
        }
        try context.save()
    }

    func saveNote(_ text: String?, moduleID: String, reference: String) throws {
        try saveText(text, kind: .note, moduleID: moduleID, reference: reference)
    }

    func saveHighlight(_ text: String?, moduleID: String, reference: String) throws {
        try saveText(text, kind: .highlight, moduleID: moduleID, reference: reference)
    }

    private func saveText(
        _ text: String?,
        kind: StudyItem.Kind,
        moduleID: String,
        reference: String
    ) throws {
        let id = Self.id(kind: kind, moduleID: moduleID, reference: reference)
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try record(id: id) {
            if let normalized, !normalized.isEmpty {
                existing.text = normalized
            } else {
                context.delete(existing)
            }
        } else if let normalized, !normalized.isEmpty {
            context.insert(
                Record(
                    id: id,
                    kind: kind.rawValue,
                    moduleID: moduleID,
                    reference: reference,
                    text: normalized
                )
            )
        }
        try context.save()
    }

    private func record(id: String) throws -> Record? {
        var descriptor = FetchDescriptor<Record>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func id(
        kind: StudyItem.Kind,
        moduleID: String,
        reference: String
    ) -> String {
        "\(kind.rawValue):\(moduleID):\(reference)"
    }

    private static func item(_ record: Record) -> StudyItem? {
        guard let kind = StudyItem.Kind(rawValue: record.kind) else { return nil }
        return StudyItem(
            kind: kind,
            moduleID: record.moduleID,
            reference: record.reference,
            text: record.text
        )
    }
}
