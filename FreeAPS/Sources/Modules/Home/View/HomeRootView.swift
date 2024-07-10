import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Override.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var fetchedPercent: FetchedResults<Override>

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        @FetchRequest(
            entity: TempTargets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var sliderTTpresets: FetchedResults<TempTargets>

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var enactedSliderTT: FetchedResults<TempTargetsSlider>

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var targetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var tirFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }

        private var spriteScene: SKScene {
            let scene = SnowScene()
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            return scene
        }

        @ViewBuilder func header(_ geo: GeometryProxy) -> some View {
            HStack(alignment: .bottom) {
                Spacer()
                cobIobView
                Spacer()
                glucoseView
                Spacer()
                pumpView
                Spacer()
                loopView
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10 + geo.safeAreaInsets.top)
            .padding(.bottom, 10)
            .background(Color.gray.opacity(0.2))
        }

        var cobIobView: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
//                    Text("IOB").font(.caption2).foregroundColor(.secondary)
                    Image("bolus1")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.insulin)
                    Text(
                        (numberFormatter.string(from: (state.suggestion?.iob ?? 0) as NSNumber) ?? "0") +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.footnote).fontWeight(.bold)
                }.frame(alignment: .bottom)
                HStack {
//                    Text("COB").font(.caption2).foregroundColor(.secondary)
                    Image("premeal")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.loopYellow)
                    Text(
                        (numberFormatter.string(from: (state.suggestion?.cob ?? 0) as NSNumber) ?? "0") +
                            NSLocalizedString(" g", comment: "gram of carbs")
                    )
                    .font(.footnote).fontWeight(.bold)
                }.frame(alignment: .top)
            }
        }

        var glucoseView: some View {
            CurrentGlucoseView(
                recentGlucose: $state.recentGlucose,
                timerDate: $state.timerDate,
                delta: $state.glucoseDelta,
                units: $state.units,
                alarm: $state.alarm,
                lowGlucose: $state.lowGlucose,
                highGlucose: $state.highGlucose,
                cgmAvailable: $state.cgmAvailable
            )
            .onTapGesture {
                state.openCGM()
            }
            .onLongPressGesture {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                state.showModal(for: .snooze)
            }
        }

        var pumpView: some View {
            PumpView(
                reservoir: $state.reservoir,
                battery: $state.battery,
                name: $state.pumpName,
                expiresAtDate: $state.pumpExpiresAtDate,
                timerDate: $state.timerDate,
                pumpStatusHighlightMessage: $state.pumpStatusHighlightMessage
            )
            .onTapGesture {
                state.setupPump = true
            }
        }

        var loopView: some View {
            LoopView(
                suggestion: $state.suggestion,
                enactedSuggestion: $state.enactedSuggestion,
                closedLoop: $state.closedLoop,
                timerDate: $state.timerDate,
                isLooping: $state.isLooping,
                lastLoopDate: $state.lastLoopDate,
                manualTempBasal: $state.manualTempBasal
            ).onTapGesture {
                isStatusPopupPresented.toggle()
            }.onLongPressGesture {
                let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                impactHeavy.impactOccurred()
                state.runLoop()
            }
        }

        var tempBasalString: String? {
            guard let tempRate = state.tempRate else {
                return nil
            }
            let rateString = numberFormatter.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if state.apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }
            return rateString + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var tempTargetString: String? {
            guard let tempTarget = state.tempTarget else {
                return nil
            }
            let target = tempTarget.targetBottom ?? 0
            let unitString = targetFormatter.string(from: (tempTarget.targetBottom?.asMmolL ?? 0) as NSNumber) ?? ""
            let rawString = (tirFormatter.string(from: (tempTarget.targetBottom ?? 0) as NSNumber) ?? "") + " " + state.units
                .rawValue

            var string = ""
            if sliderTTpresets.first?.active ?? false {
                let hbt = sliderTTpresets.first?.hbt ?? 0
                string = ", " + (tirFormatter.string(from: state.infoPanelTTPercentage(hbt, target) as NSNumber) ?? "") + " %"
            }

            let percentString = state
                .units == .mmolL ? (unitString + " mmol/L" + string) : (rawString + (string == "0" ? "" : string))
            return tempTarget.displayName + " " + percentString
        }

        var overrideString: String? {
            guard fetchedPercent.first?.enabled ?? false else {
                return nil
            }
            var percentString = "\((fetchedPercent.first?.percentage ?? 100).formatted(.number)) %"
            var target = (fetchedPercent.first?.target ?? 100) as Decimal
            let indefinite = (fetchedPercent.first?.indefinite ?? false)
            let unit = state.units.rawValue
            if state.units == .mmolL {
                target = target.asMmolL
            }
            var targetString = (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
            if tempTargetString != nil || target == 0 { targetString = "" }
            percentString = percentString == "100 %" ? "" : percentString

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            var newDuration: Decimal = 0

            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() {
                newDuration = Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes)
            }

            var durationString = indefinite ?
                "" : newDuration >= 1 ?
                (newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " min") :
                (
                    newDuration > 0 ? (
                        (newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0))) + " s"
                    ) :
                        ""
                )

            if durationString == "", !indefinite {
                return nil
            }

            let smbToggleString = (
                (fetchedPercent.first?.smbIsOff ?? false) || fetchedPercent.first?.smbIsScheduledOff ?? false
            ) ?
                " \u{20e0}" : ""
            let smbScheduleString = (fetchedPercent.first?.smbIsScheduledOff ?? false) &&
                !(fetchedPercent.first?.smbIsOff ?? false) ?
                " \(fetchedPercent.first?.start ?? 0)-\(fetchedPercent.first?.end ?? 0)" : ""
            let comma1 = (percentString == "" || (targetString == "" && durationString == "" && smbToggleString == ""))
                ? "" : " , "
            let comma2 = (targetString == "" || (durationString == "" && smbToggleString == ""))
                ? "" : " , "
            let comma3 = (durationString == "" || smbToggleString == "")
                ? "" : " , "

            return percentString + comma1 + targetString + comma2 + durationString + comma3 + smbToggleString + smbScheduleString
        }

        var infoPanel: some View {
            HStack(alignment: .center) {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempBasalString = tempBasalString {
                    Text(tempBasalString)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.insulin)
                        .padding(.leading, 8)
                }

                if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let overrideString = overrideString {
                    Text("👤 " + overrideString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.trailing, 8)
                }

                if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                    Text("Max IOB: 0").font(.callout).foregroundColor(.orange).padding(.trailing, 20)
                }

                if let currentISF = state.isf {
                    Text("ISF:")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .fixedSize()
                    if state.units == .mmolL {
                        Text(
                            glucoseFormatter
                                .string(from: currentISF.asMmolL as NSNumber) ?? " "
                        )
                        .font(.system(size: 12, weight: .bold)).fixedSize()
                    } else {
                        Text(
                            glucoseFormatter
                                .string(from: currentISF as NSNumber) ?? " "
                        )
                        .font(.system(size: 12, weight: .bold)).fixedSize()
                    }
                }

                if let progress = state.bolusProgress {
                    Text("Bolusing")
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    ProgressView(value: Double(progress))
                        .progressViewStyle(BolusProgressViewStyle())
                        .padding(.trailing, 8)
                        .onTapGesture {
                            state.cancelBolus()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        var legendPanel: some View {
            ZStack {
                HStack(alignment: .center) {
                    Group {
                        Text(
                            "TDD " + (numberFormatter.string(from: (state.suggestion?.tdd ?? 0) as NSNumber) ?? "0")
                        ).font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                        Text(
                            "ytd. " + (numberFormatter.string(from: (state.suggestion?.tddytd ?? 0) as NSNumber) ?? "0")
                        ).font(.system(size: 12, weight: .regular)).foregroundColor(.insulin)
                    }
                    Text(" | ").foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .light))
                    Group {
                        Circle().fill(Color.zt).frame(width: 8, height: 8)
                        Text("ZT")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.zt)
                    }
                    Group {
                        Circle().fill(Color.insulin).frame(width: 8, height: 8)
                        Text("IOB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    }
                    Group {
                        Circle().fill(Color.uam).frame(width: 8, height: 8)
                        Text("UAM")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.uam)
                    }
                    Group {
                        Circle().fill(Color.loopYellow).frame(width: 8, height: 8)
                        Text("COB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.loopYellow)
                    }
                    if let eventualBG = state.eventualBG {
                        Text(" | ").foregroundColor(.secondary)
                            .font(.system(size: 12, weight: .light))
                        Text(
                            "⇢ " + glucoseFormatter.string(
                                from: (state.units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
                            )!
                        )
                        .font(.system(size: 12, weight: .bold)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding([.vertical], 8)
            }
        }

        var mainChart: some View {
            ZStack {
                if state.animatedBackground {
                    SpriteView(scene: spriteScene, options: [.allowsTransparency])
                        .ignoresSafeArea()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                }

                MainChartView(
                    glucose: $state.glucose,
                    suggestion: $state.suggestion,
                    tempBasals: $state.tempBasals,
                    boluses: $state.boluses,
                    suspensions: $state.suspensions,
                    hours: .constant(state.filteredHours),
                    maxBasal: $state.maxBasal,
                    autotunedBasalProfile: $state.autotunedBasalProfile,
                    basalProfile: $state.basalProfile,
                    tempTargets: $state.tempTargets,
                    carbs: $state.carbs,
                    timerDate: $state.timerDate,
                    units: $state.units,
                    smooth: $state.smooth,
                    highGlucose: $state.highGlucose,
                    lowGlucose: $state.lowGlucose,
                    screenHours: $state.screenHours,
                    displayXgridLines: $state.displayXgridLines,
                    displayYgridLines: $state.displayYgridLines,
                    thresholdLines: $state.thresholdLines
                )
            }
            .padding(.bottom)
            .modal(for: .dataTable, from: self)
        }

        @ViewBuilder private func profiles(_: GeometryProxy) -> some View {
            let colour: Color = colorScheme == .dark ? .black : .white
            // Rectangle().fill(colour).frame(maxHeight: 1)
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(maxHeight: 40)
                let cancel = fetchedPercent.first?.enabled ?? false
                HStack(spacing: cancel ? 25 : 15) {
                    Text(selectedProfile().name).foregroundColor(.secondary)
                    if cancel, selectedProfile().isOn {
                        Button { showCancelAlert.toggle() }
                        label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button { state.showModal(for: .overrideProfilesConfig) }
                    label: {
                        Image(systemName: "person.3.sequence.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                !(fetchedPercent.first?.enabled ?? false) ? .green : .cyan,
                                !(fetchedPercent.first?.enabled ?? false) ? .cyan : .green,
                                .purple
                            )
                    }
                }
            }
            .alert(
                "Return to Normal?", isPresented: $showCancelAlert,
                actions: {
                    Button("No", role: .cancel) {}
                    Button("Yes", role: .destructive) {
                        state.cancelProfile()
                    }
                }, message: { Text("This will change settings back to your normal profile.") }
            )
            Rectangle().fill(colour).frame(maxHeight: 1)
        }

        private func selectedProfile() -> (name: String, isOn: Bool) {
            var profileString = ""
            var display: Bool = false

            let duration = (fetchedPercent.first?.duration ?? 0) as Decimal
            let indefinite = fetchedPercent.first?.indefinite ?? false
            let addedMinutes = Int(duration)
            let date = fetchedPercent.first?.date ?? Date()
            if date.addingTimeInterval(addedMinutes.minutes.timeInterval) > Date() || indefinite {
                display.toggle()
            }

            if fetchedPercent.first?.enabled ?? false, !(fetchedPercent.first?.isPreset ?? false), display {
                profileString = NSLocalizedString("Custom Profile", comment: "Custom but unsaved Profile")
            } else if !(fetchedPercent.first?.enabled ?? false) || !display {
                profileString = NSLocalizedString("Normal Profile", comment: "Your normal Profile. Use a short string")
            } else {
                let id_ = fetchedPercent.first?.id ?? ""
                let profile = fetchedProfiles.filter({ $0.id == id_ }).first
                if profile != nil {
                    profileString = profile?.name?.description ?? ""
                }
            }
            return (name: profileString, isOn: display)
        }

        @ViewBuilder private func bottomPanel(_ geo: GeometryProxy) -> some View {
            let colorIcon: Color = (colorScheme == .dark ? Color.loopGray : Color.black).opacity(0.9)
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 50 + geo.safeAreaInsets.bottom)

                HStack(alignment: .bottom) {
                    Button { state.showModal(for: .addCarbs) }
                    label: {
                        ZStack(alignment: Alignment(horizontal: .trailing, vertical: .bottom)) {
                            Image("carbs1")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 30, height: 30)
//                                .foregroundColor(.loopYellow)
                                .padding(8)
                            if let carbsReq = state.carbsRequired {
                                Text(numberFormatter.string(from: carbsReq as NSNumber)!)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                    Spacer()
                    Button {
                        state.showModal(for: .bolus(
                            waitForSuggestion: true
                        ))
                    }
                    label: {
                        Image("bolus")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 30, height: 30)
//                            .foregroundColor(.insulin)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                    Spacer()
//                    Button { state.showModal(for: .addTempTarget) }
//                    label: {
//                        Image("target1")
//                            .renderingMode(.template)
//                            .resizable()
//                            .frame(width: 30, height: 30)
                    ////                            .foregroundColor(.loopGreen)
//                            .padding(8)
//                    }
//                    .foregroundColor(colorIcon)
//                    .buttonStyle(.borderless)
                    Image("target1")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .padding(8)
//                        .foregroundColor(.loopGreen)
                        .onTapGesture { state.showModal(for: .addTempTarget) }
                        .onLongPressGesture {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.showModal(for: .overrideProfilesConfig)
                        }
                        .foregroundColor(colorIcon)
                        .buttonStyle(.borderless)
                    Spacer()
                    if state.allowManualTemp {
                        Button { state.showModal(for: .manualTempBasal) }
                        label: {
                            Image("bolus1")
                                .renderingMode(.template)
                                .resizable()
//                                .foregroundColor(.basal)
                                .frame(width: 30, height: 30)
                                .padding(8)
                        }
                        .foregroundColor(colorIcon)
                        .buttonStyle(.borderless)
                        Spacer()
                    }

                    // overide profiles
//                    Button {
//                        state.showModal(for: .overrideProfilesConfig)
//                    } label: {
//                        Image(systemName: "person")
//                            .font(.system(size: 30, weight: .light))
//                            .padding(8)
//                    }
//                    .foregroundColor(colorIcon)
//                    .buttonStyle(.borderless)
//                    Spacer()

                    Image("statistics")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 30, height: 30)
                        .padding(8)
//                        .foregroundColor(.uam)
                        .onTapGesture { state.showModal(for: .statistics) }
                        .onLongPressGesture {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.showModal(for: .autoisf)
                        }
                        .foregroundColor(colorIcon)
                        .buttonStyle(.borderless)

                    Spacer()
                    Button { state.showModal(for: .settings) }
                    label: {
                        Image("settings")
                            .renderingMode(.template)
                            .resizable()
//                                .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .padding(8)
                    }
                    .foregroundColor(colorIcon)
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, geo.safeAreaInsets.bottom - 10)
            }
        }

        var body: some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header(geo)
                    Divider().background(Color.gray)
                    infoPanel
                    mainChart
                    Divider().background(Color.gray)
                    legendPanel
//                    profiles(geo)
                    bottomPanel(geo)
                }
                .edgesIgnoringSafeArea(.vertical)
            }
            .onAppear(perform: configureView)
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: isStatusPopupPresented, alignment: .top, direction: .top) {
                VStack {
                    Rectangle().opacity(0).frame(height: 95)
                    popup
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(colorScheme == .dark ? Color(
                                    red: 0.05490196078,
                                    green: 0.05490196078,
                                    blue: 0.05490196078
                                ) : Color(UIColor.darkGray))
                        )
                        // .opacity(0.8)
                        .onTapGesture {
                            isStatusPopupPresented = false
                        }
                        .gesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.height < 0 {
                                        isStatusPopupPresented = false
                                    }
                                }
                        )
                }
            }
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.statusTitle).font(.headline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let suggestion = state.suggestion {
                    TagCloudView(tags: suggestion.reasonParts).animation(.none, value: false)

                    Text(suggestion.reasonConclusion.capitalizingFirstLetter()).font(.caption).foregroundColor(.white)

                } else {
                    Text("No sugestion found").font(.body).foregroundColor(.white)
                }

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.caption).foregroundColor(.loopRed)
                } else if let suggestion = state.suggestion, (suggestion.bg ?? 100) == 400 {
                    Text("Invalid CGM reading (HIGH).").font(.callout).bold().foregroundColor(.loopRed).padding(.top, 8)
                    Text("SMBs and High Temps Disabled.").font(.caption).foregroundColor(.white).padding(.bottom, 4)
                }
            }
        }
    }
}
