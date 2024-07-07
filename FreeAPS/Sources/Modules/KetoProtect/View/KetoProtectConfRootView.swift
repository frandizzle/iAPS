import SwiftUI
import Swinject

extension KetoConf {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            return formatter
        }

        @State private var infoButtonPressed: InfoText?
        @Environment(\.colorScheme) var colorScheme

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
                Section {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Toggle("Activate KetoProtect", isOn: $state.ketoProtect)
                        }
                        .padding(.bottom, 2)
                        if !state.ketoProtect {
                            Text(
                                "Ketoacidosis protection will apply a small configurable Temp Basal Rate always or if certain conditions arise instead of a Zero temp!\nThe feature exists because in special cases a person could get ketoacidosis from 0% TBR. The idea is derived from sport. There could be problems when a basal rate of 0% ran for several hours. Muscles in particular could shut off.\nThis feature enables a small safety TBR to reduce the ketoacidosis risk. Without the Variable Protection that safety TBR is always applied. The idea behind the variable protection strategy is that the safety TBR is only applied if sum of basal-IOB and bolus-IOB falls negatively below the value of the current basal rate."
                            )
                        }
                    }
                } header: { Text("Enable").textCase(nil) }
                if state.ketoProtect {
                    ForEach(state.sections.indexed(), id: \.1.id) { sectionIndex, section in
                        Section(header: Text(section.displayName).textCase(nil)) {
                            ForEach(section.fields.indexed(), id: \.1.id) { fieldIndex, field in
                                HStack {
                                    switch field.type {
                                    case .boolean:
                                        ZStack {
                                            Button("", action: {
                                                infoButtonPressed = InfoText(
                                                    description: field.infoText,
                                                    oref0Variable: field.displayName
                                                )
                                            })
                                            Toggle(isOn: self.$state.sections[sectionIndex].fields[fieldIndex].boolValue) {
                                                Text(field.displayName)
                                            }
                                        }
                                    case .decimal:
                                        ZStack {
                                            Button("", action: {
                                                infoButtonPressed = InfoText(
                                                    description: field.infoText,
                                                    oref0Variable: field.displayName
                                                )
                                            })
                                            Text(field.displayName)
                                        }
                                        DecimalTextField(
                                            "0",
                                            value: self.$state.sections[sectionIndex].fields[fieldIndex].decimalValue,
                                            formatter: formatter
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Ketoacidosis Protection Configuration")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(item: $infoButtonPressed) { infoButton in
                Alert(
                    title: Text("\(infoButton.oref0Variable)"),
                    message: Text("\(infoButton.description)"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onDisappear {
                state.saveIfChanged()
            }
        }

        func createParagraphAttribute(
            tabStopLocation: CGFloat,
            defaultTabInterval: CGFloat,
            firstLineHeadIndent: CGFloat,
            headIndent: CGFloat
        ) -> NSParagraphStyle {
            let paragraphStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
            let options: [NSTextTab.OptionKey: Any] = [:]
            paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: tabStopLocation, options: options)]
            paragraphStyle.defaultTabInterval = defaultTabInterval
            paragraphStyle.firstLineHeadIndent = firstLineHeadIndent
            paragraphStyle.headIndent = headIndent
            return paragraphStyle
        }
    }
}
