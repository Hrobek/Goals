//
//  WidgetPageStore.swift
//  Goals
//

import Foundation

/// Which page each widget is currently showing. A widget can't scroll, so the ‹ › buttons write
/// the new page here and ask WidgetKit to redraw; the timeline provider reads it back on the way
/// out. Keyed per widget kind *and* size, so a small and a large widget sitting on the same screen
/// page independently of each other.
enum WidgetPageStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedStore.appGroupID)
    }

    static func page(forKey key: String) -> Int {
        defaults?.integer(forKey: storageKey(key)) ?? 0
    }

    static func setPage(_ page: Int, forKey key: String) {
        defaults?.set(page, forKey: storageKey(key))
    }

    /// Wraps a page index into `0..<count`. The arrows loop rather than dead-end: a greyed-out
    /// chevron on a home screen gives no hint why it stopped working, and looping keeps both taps
    /// meaningful however many goals there are.
    static func wrapped(_ page: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((page % count) + count) % count
    }

    private static func storageKey(_ key: String) -> String {
        "Goals.widgetPage.\(key)"
    }
}
