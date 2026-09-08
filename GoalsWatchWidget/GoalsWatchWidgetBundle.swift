//
//  GoalsWatchWidgetBundle.swift
//  GoalsWatchWidget
//

import WidgetKit
import SwiftUI

@main
struct GoalsWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayTallyComplication()
        NextHabitComplication()
    }
}
