import SwiftUI

struct AutoDIAHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [AutoDIAHistoryEntry]

    var body: some View {
        // Only show entries from last 24 hours
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recentEntries = entries.filter { $0.timestamp >= cutoff }

        NavigationView {
            Group {
                if recentEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.6))

                        Text("No AutoDIA calibrations in the last 24 hours")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Text("A new entry will appear here each time AutoDIA recalibrates DIA & Peak time.")
                            .font(.subheadline)
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 40)
                    .ignoresSafeArea(.container, edges: .bottom)

                } else {
                    List(recentEntries.sorted(by: { $0.timestamp > $1.timestamp })) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)

                            Text("DIA: \(String(format: "%.1f", entry.diaHours)) hours")
                            Text("Peak: \(Int(entry.peakMinutes)) minutes")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("AutoDIA History (24H)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.headline)
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
}
