//
//  GoalsWidgetBundle.swift
//  GoalsWidget
//

import WidgetKit
import SwiftUI

@main
struct GoalsWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoalsWidget()
        SingleGoalWidget()
        HabitsWidget()
        // iOS 27's full-page extra-large portrait size - a combined Today widget only makes sense
        // once that size exists to hold both lists.
        if #available(iOS 27.0, *) {
            TodayWidget()
        }
    }
}
