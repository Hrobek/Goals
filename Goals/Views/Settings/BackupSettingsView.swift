//
//  BackupSettingsView.swift
//  Goals
//

import SwiftUI
import SwiftData
import WidgetKit
import UniformTypeIdentifiers

/// Export the signed-in user's whole account to a JSON file, or replace it from one. Pushed from
/// the General section of Settings.
struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSession.self) private var session

    @State private var exportDocument: JSONFile?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: PendingImport?
    @State private var errorMessage: String?
    @State private var didImport = false

    private var userId: UUID { session.currentUser?.id ?? Goal.unownedId }

    struct PendingImport: Identifiable {
        let id = UUID()
        let document: DataTransfer.Document
        var summary: DataTransfer.Summary { DataTransfer.summary(of: document) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                CardGroup {
                    Button { startExport() } label: {
                        row("backup.export", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)

                    RowDivider()

                    Button { isImporting = true } label: {
                        row("backup.import", icon: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                }

                Text("backup.explainer")
                    .font(Theme.Typo.footnote)
                    .foregroundStyle(Theme.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                if didImport {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textFaint)
                        Text("backup.imported")
                            .font(Theme.Typo.footnote)
                            .foregroundStyle(Theme.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.surfaceMuted, in: .rect(cornerRadius: Theme.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card)
                            .strokeBorder(Theme.hairlineSoft, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.screen)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .screenGround()
        .navigationTitle("backup.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ground, for: .navigationBar)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
            exportDocument = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handlePickedFile(result)
        }
        .alert(
            "backup.import.confirm.title",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { pending in
            Button("backup.import.confirm.replace", role: .destructive) {
                performImport(pending.document)
            }
            Button("action.cancel", role: .cancel) {}
        } message: { pending in
            Text("backup.import.confirm.message \(pending.summary.goals) \(pending.summary.habits) \(formatted(pending.summary.exportedAt))")
        }
        .alert(
            "backup.error.title",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("action.ok", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Rows

    private func row(_ label: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(label)
                .font(Theme.Typo.row)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 10)
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }

    // MARK: - Export

    private var exportFilename: String {
        "Goals-\(Date.now.formatted(.iso8601.year().month().day()))"
    }

    private func startExport() {
        do {
            let data = try DataTransfer.export(userId: userId, context: modelContext)
            exportDocument = JSONFile(data: data)
            isExporting = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import

    private func handlePickedFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingImport = PendingImport(document: try DataTransfer.decode(data))
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func performImport(_ document: DataTransfer.Document) {
        do {
            try DataTransfer.replaceAll(with: document, userId: userId, context: modelContext)
            pendingImport = nil
            didImport = true
            WidgetCenter.shared.reloadAllTimelines()
            let userId = userId
            Task { await NotificationScheduler.syncAll(context: modelContext, userId: userId) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// The tiny file wrapper `fileExporter` needs — it only ever carries the encoded backup bytes.
struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    NavigationStack {
        BackupSettingsView()
            .environment(AuthSession())
    }
}
