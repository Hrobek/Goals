//
//  PageIntent.swift
//  GoalsWidget
//

import AppIntents
import WidgetKit

/// The ‹ › buttons. A widget can't scroll, so paging is a write plus a redraw: store the new page
/// in the App Group and ask WidgetKit to rebuild this kind of widget, which sends the provider
/// back for the next slice of goals.
struct PageIntent: AppIntent {
    static var title: LocalizedStringResource { "Show other goals" }
    static var description: IntentDescription { "Pages the widget through the goals that don't fit on it." }

    // Defaults matter: a non-optional @Parameter with none is not reliably archived into a widget
    // `Button(intent:)`, so the tap never reaches `perform()`.

    /// Widget kind, so only the widgets that actually changed get rebuilt.
    @Parameter(title: "Kind", default: "")
    var kind: String

    /// Page-store key — the kind plus the widget's size.
    @Parameter(title: "Scope", default: "")
    var scope: String

    @Parameter(title: "Step", default: 0)
    var step: Int

    @Parameter(title: "Pages", default: 1)
    var pageCount: Int

    init() {}

    init(kind: String, scope: String, step: Int, pageCount: Int) {
        self.kind = kind
        self.scope = scope
        self.step = step
        self.pageCount = pageCount
    }

    func perform() async throws -> some IntentResult {
        let next = WidgetPageStore.wrapped(WidgetPageStore.page(forKey: scope) + step, count: pageCount)
        WidgetPageStore.setPage(next, forKey: scope)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        return .result()
    }
}
