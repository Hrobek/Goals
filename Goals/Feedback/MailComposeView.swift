//
//  MailComposeView.swift
//  Goals
//

import SwiftUI
import MessageUI

/// Thin SwiftUI wrapper around the system mail composer — the no-backend way to accept
/// feedback with screenshot/video attachments.
struct MailComposeView: UIViewControllerRepresentable {
    let report: FeedbackReport
    let attachments: [FeedbackAttachment]
    let onFinish: (MFMailComposeResult) -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([SupportContact.email])
        controller.setSubject(report.subject)
        controller.setMessageBody(report.body, isHTML: false)
        for attachment in attachments {
            controller.addAttachmentData(attachment.data, mimeType: attachment.mimeType, fileName: attachment.filename)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}
