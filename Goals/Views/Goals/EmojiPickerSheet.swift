//
//  EmojiPickerSheet.swift
//  Goals
//

import SwiftUI

struct EmojiPickerSheet: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    private static let options = [
        "🎯", "📚", "💪", "🏃", "🏋️", "🧘", "🎨", "✍️", "🎓", "💰",
        "🥗", "💧", "😴", "🚴", "🎸", "🧠", "❤️", "🌱", "🧹", "💼",
        "🔥", "⭐️", "☀️", "🌙", "🍎", "🚭", "📈", "🧴", "🎵", "🧩"
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Self.options, id: \.self) { emoji in
                        Button {
                            selection = emoji
                            dismiss()
                        } label: {
                            Text(emoji).font(.largeTitle)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("goal.field.emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                if selection != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("action.clear") {
                            selection = nil
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    EmojiPickerSheet(selection: .constant(nil))
}
