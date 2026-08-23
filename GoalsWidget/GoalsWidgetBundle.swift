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
        ActivityWidget()
        ProgressChartWidget()
    }
}
