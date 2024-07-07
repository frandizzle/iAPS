import CoreData
import SwiftUI
import Swinject

extension AddTempTarget {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isPromptPresented = false
        @State private var isRemoveAlertPresented = false
        @State private var removeAlert: Alert?
        @State private var isEditing = false

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var isEnabledArray: FetchedResults<TempTargetsSlider>

        @Environment(\.colorScheme) var colorScheme

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        var body: some View {
            Form {
                if state.storage?.current() != nil {
                    Section {
                        Button { state.cancel() }
                        label: { Text("Cancel current TempTarget") }
                            .disabled(state.storage?.current() == nil)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .buttonStyle(BorderlessButtonStyle())
                            .tint(.red)
                    }
                }

                if !state.presets.isEmpty {
                    Section(header: Text("Presets")) {
                        ForEach(state.presets) { preset in
                            presetView(for: preset)
                        }
                    }
                }

                HStack {
                    Text("Advanced TT")
                    Toggle(isOn: $state.viewPercantage) {}.controlSize(.mini)
                    Image(systemName: "figure.highintensity.intervaltraining")
                    Image(systemName: "fork.knife")
                }

                if state.viewPercantage {
                    Section(
                        header: Text("TT Effect on Insulin")
                    ) {
                        VStack {
                            HStack {
                                Text(NSLocalizedString("Target", comment: ""))
                                Spacer()
                                DecimalTextField(
                                    "0",
                                    value: $state.low,
                                    formatter: formatter,
                                    cleanInput: true
                                )
                                Text(state.units.rawValue).foregroundColor(.secondary)
                            }

                            if computeSliderLow() != computeSliderHigh() {
                                Text("\(state.percentage.formatted(.number)) % Insulin")
                                    .foregroundColor(isEditing ? .orange : .blue)
                                    .font(.largeTitle)
                                Slider(
                                    value: $state.percentage,
                                    in: computeSliderLow() ... computeSliderHigh(),
                                    step: 5
                                ) {}
                                minimumValueLabel: { Text("\(computeSliderLow(), specifier: "%.0f")%") }
                                maximumValueLabel: { Text("\(computeSliderHigh(), specifier: "%.0f")%") }
                                onEditingChanged: { editing in
                                    isEditing = editing }
                                Divider()
                                Text(
                                    state
                                        .units == .mgdL ?
                                        "Half Basal Exercise Target at: \(state.computeHBT().formatted(.number)) mg/dl" :
                                        "Half Basal Exercise Target at: \(state.computeHBT().asMmolL.formatted(.number.grouping(.never).rounded().precision(.fractionLength(1)))) mmol/L"
                                )
                                .foregroundColor(.secondary)
                                .font(.caption).italic()
                            } else {
                                Text(
                                    "You have not enabled the proper Preferences to change sensitivity with chosen TempTarget. Verify Autosens Max > 1 & lowTT lowers Sens is on for lowTT's. For high TTs check highTT raises Sens is on (or Exercise Mode)!"
                                )
                                // .foregroundColor(.loopRed)
                                .font(.caption).italic()
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                            }
                        }
                    }
                } else {
                    Section(header: Text("Custom")) {
                        HStack {
                            Text("Target")
                            Spacer()
                            DecimalTextField("0", value: $state.low, formatter: formatter, cleanInput: true)
                            Text(state.units.rawValue).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                    }
                }
                if state.viewPercantage {
                    Section {
                        HStack {
                            Text("Duration")
                            Spacer()
                            DecimalTextField("0", value: $state.duration, formatter: formatter, cleanInput: true)
                            Text("minutes").foregroundColor(.secondary)
                        }
                        DatePicker("Date", selection: $state.date)
                        Button { isPromptPresented = true }
                        label: { Text("Save as preset") }
                            .disabled(state.duration == 0)
                    }
                }

                Section {
                    Button { state.enact() }
                    label: { Text("Start") }
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .popover(isPresented: $isPromptPresented) {
                Form {
                    Section(header: Text("Enter preset name")) {
                        TextField("Name", text: $state.newPresetName)
                        Button {
                            state.save()
                            isPromptPresented = false
                        }
                        label: { Text("Save") }
                        Button { isPromptPresented = false }
                        label: { Text("Cancel") }
                    }
                }
                .scrollContentBackground(.hidden).background(color)
            }
            .onAppear {
                configureView()
                state.hbt = isEnabledArray.first?.hbt ?? 160
            }
            .navigationTitle("Enact Temp Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        state.hideModal()
                    }
                }
            }
        }

        private func presetView(for preset: TempTarget) -> some View {
            var low = preset.targetBottom
            var high = preset.targetTop
            if state.units == .mmolL {
                low = low?.asMmolL
                high = high?.asMmolL
            }
            return HStack {
                VStack {
                    HStack {
                        Text(preset.displayName)
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        Text(
                            "\(formatter.string(from: (low ?? 0) as NSNumber)!)" // - \(formatter.string(from: (high ?? 0) as NSNumber)!)"
                        )
                        .foregroundColor(.secondary)
                        .font(.caption)

                        Text(state.units.rawValue)
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("for")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(formatter.string(from: preset.duration as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Spacer()
                    }.padding(.top, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.enactPreset(id: preset.id)
                }

                Image(systemName: "xmark.circle").foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .padding(.vertical)
                    .onTapGesture {
                        removeAlert = Alert(
                            title: Text("Are you sure?"),
                            message: Text("Delete preset \"\(preset.displayName)\""),
                            primaryButton: .destructive(Text("Delete"), action: { state.removePreset(id: preset.id) }),
                            secondaryButton: .cancel()
                        )
                        isRemoveAlertPresented = true
                    }
                    .alert(isPresented: $isRemoveAlertPresented) {
                        removeAlert!
                    }
            }
        }

        func computeSliderLow() -> Double {
            var minSens: Double = 15
            var target = state.low
            if state.units == .mmolL {
                target = Decimal(round(Double(state.low.asMgdL))) }
            if target == 0 { return minSens }
            if target < 100 ||
                (
                    !state.settingsManager.preferences.highTemptargetRaisesSensitivity && !state.settingsManager.preferences
                        .exerciseMode
                ) { minSens = 100 }
            return minSens
        }

        func computeSliderHigh() -> Double {
            var maxSens = Double(state.maxValue * 100)
            var target = state.low
            if target == 0 { return maxSens }
            if state.units == .mmolL {
                target = Decimal(round(Double(state.low.asMgdL))) }
            if target > 100 || !state.settingsManager.preferences.lowTemptargetLowersSensitivity { maxSens = 100 }
            return maxSens
        }
    }
}
