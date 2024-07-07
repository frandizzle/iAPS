import SwiftUI

struct CustomDateTimePicker: UIViewRepresentable {
    @Binding var selection: Date
    var minuteInterval: Int // Hold the custom interval value

    // Coordinator to handle date changes
    class Coordinator: NSObject {
        var parent: CustomDateTimePicker

        init(_ parent: CustomDateTimePicker) {
            self.parent = parent
        }

        @objc func dateChanged(_ sender: UIDatePicker) {
            parent.selection = sender.date
        }
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let datePicker = UIDatePicker()
        datePicker.datePickerMode = .dateAndTime
        datePicker.minuteInterval = minuteInterval // Use the custom interval

        // Set up the date change action
        datePicker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)

        return datePicker
    }

    func updateUIView(_ uiView: UIDatePicker, context _: Context) {
        uiView.date = selection
        uiView.minuteInterval = minuteInterval // Ensure interval is updated if changed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}
