import SwiftUI
import Swinject

extension AutoISFConf {
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
                            Toggle("Activate autoISF", isOn: $state.autoisf)
                        }
                        .padding(.bottom, 2)
                        if !state.autoisf {
                            VStack(alignment: .leading) {
                                Text(
                                    "autoISF allows to adapt the insulin sensitivity factor (ISF) in the following scenarios of glucose behaviour:"
                                )
                                BulletList(
                                    listItems:
                                    [
                                        "accelerating/decelerating blood glucose",
                                        "blood glucose levels according to a predefined polygon, like a Sigmoid",
                                        "postprandial (after meal) glucose rise",
                                        "blood glucose plateaus above target"
                                    ],
                                    listItemSpacing: 10
                                )
                            }
                            // .padding(10)
                            Text("It can also adapt SMB delivery settings.")
                            Text(
                                "Read up on it at:\nhttps://github.com/ga-zelle/autoISF\nHit View Code to access all help documents!\niAPS version of autoISF does not include ActivityTracking."
                            )
                        }
                    }
                } header: { Text("Enable").textCase(nil) }
                if state.autoisf {
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
            .navigationTitle("autoISF Configuration")
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
