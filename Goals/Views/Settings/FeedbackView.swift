//
//  FeedbackView.swift
//  Goals
//

import SwiftUI
import PhotosUI
import MessageUI
import UniformTypeIdentifiers

struct FeedbackView: View {
    /// Mail attachments get rejected by most providers well before this, and huge videos are the
    /// usual culprit — so the limit is enforced here rather than at send time.
    /// Decimal megabytes, so the formatted limit in the UI reads "20 MB" and not "21 MB".
    private static let maxTotalBytes = 20_000_000

    @Environment(\.dismiss) private var dismiss

    @State private var kind: FeedbackKind = .bug
    @State private var message = ""
    @State private var attachments: [FeedbackAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingAttachments = false

    @State private var isShowingMailComposer = false
    @State private var isShowingMailUnavailable = false
    @State private var isShowingTooLarge = false
    @State private var didCopyReport = false

    private var report: FeedbackReport {
        FeedbackReport(kind: kind, message: message)
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var totalBytes: Int {
        attachments.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        Form {
            Section {
                Picker("feedback.kind", selection: $kind) {
                    ForEach(FeedbackKind.allCases) { kind in
                        Text(kind.localizedName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("feedback.message") {
                TextField("feedback.message.placeholder", text: $message, axis: .vertical)
                    .lineLimit(5...12)
            }

            Section {
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment)
                }
                .onDelete { offsets in
                    attachments.remove(atOffsets: offsets)
                }

                PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos])) {
                    Label("feedback.addAttachment", systemImage: "paperclip")
                }
                .disabled(isLoadingAttachments)
            } header: {
                Text("feedback.attachments")
            } footer: {
                Text("feedback.attachments.footer \(Self.maxTotalBytes.formatted(.byteCount(style: .file)))")
            }

            Section {
                DisclosureGroup("feedback.diagnostics") {
                    Text(Diagnostics.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("feedback.diagnostics.footer")
            }
        }
        .navigationTitle("feedback.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("action.send") { send() }
                    .disabled(!canSend || isLoadingAttachments)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
        .sheet(isPresented: $isShowingMailComposer) {
            MailComposeView(report: report, attachments: attachments) { result in
                if result == .sent {
                    dismiss()
                }
            }
            .ignoresSafeArea()
        }
        .alert("feedback.mailUnavailable.title", isPresented: $isShowingMailUnavailable) {
            Button("feedback.copyReport") {
                UIPasteboard.general.string = "\(report.subject)\n\n\(report.body)"
                didCopyReport = true
            }
            Button("action.ok", role: .cancel) {}
        } message: {
            Text("feedback.mailUnavailable.message \(SupportContact.email)")
        }
        .alert("feedback.copied", isPresented: $didCopyReport) {
            Button("action.ok", role: .cancel) {}
        }
        .alert("feedback.tooLarge.title", isPresented: $isShowingTooLarge) {
            Button("action.ok", role: .cancel) {}
        } message: {
            Text("feedback.tooLarge.message \(Self.maxTotalBytes.formatted(.byteCount(style: .file)))")
        }
    }

    /// Above a full-resolution screenshot's long edge, so screenshots stay pixel-exact while
    /// 12MP camera photos get cut down.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat = 3000) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        // Scale 1, or the renderer would draw at the screen's 3× and hand back an image bigger
        // than the one we're trying to shrink.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func send() {
        if MailComposeView.canSendMail {
            isShowingMailComposer = true
        } else {
            isShowingMailUnavailable = true
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        isLoadingAttachments = true
        defer {
            isLoadingAttachments = false
            pickerItems = []
        }

        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }

            let type = item.supportedContentTypes.first
            let isVideo = type?.conforms(to: .movie) ?? false

            let data: Data
            let ext: String
            let mimeType: String
            let preview: UIImage?

            if isVideo {
                data = raw
                ext = type?.preferredFilenameExtension ?? "mov"
                mimeType = type?.preferredMIMEType ?? "video/quicktime"
                preview = nil
            } else if let image = UIImage(data: raw).map({ Self.downscaled($0) }),
                      let jpeg = image.jpegData(compressionQuality: 0.85) {
                // Re-encoding drops the EXIF the picker warns about (location, capture time);
                // downscaling keeps a couple of camera photos inside the size limit.
                data = jpeg
                ext = "jpg"
                mimeType = "image/jpeg"
                preview = image
            } else {
                continue
            }

            guard totalBytes + data.count <= Self.maxTotalBytes else {
                isShowingTooLarge = true
                continue
            }

            attachments.append(
                FeedbackAttachment(
                    data: data,
                    filename: "attachment-\(attachments.count + 1).\(ext)",
                    mimeType: mimeType,
                    isVideo: isVideo,
                    preview: preview
                )
            )
        }
    }
}

private struct AttachmentRow: View {
    let attachment: FeedbackAttachment

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                if let preview = attachment.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: attachment.isVideo ? "film" : "doc")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(attachment.byteCount.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
    }
}
