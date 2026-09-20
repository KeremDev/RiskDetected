#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// The eleven-step questionnaire: sticky progress header, one of five answer
/// widgets, and the sticky primary/skip footer.
struct NovaOBQuestionScreen: View {
    @ObservedObject var controller: NovaOBController
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock
                    answerWidget
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(NovaOB.surface.ignoresSafeArea())
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                NovaOBBackButton { controller.back() }
                    .padding(.leading, -12)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaOB.line)
                        Capsule()
                            .fill(NovaOB.ink)
                            .frame(width: proxy.size.width * controller.progress)
                            .animation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.28), value: controller.progress)
                    }
                }
                .frame(height: 4)
                Text(controller.stepLabel)
                    .font(NovaOB.font(13.5))
                    .monospacedDigit()
                    .foregroundColor(NovaOB.muted)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            Text(controller.sectionLabel)
                .font(NovaOB.font(11.5, 600))
                .tracking(1.495)
                .foregroundColor(NovaOB.ink)
        }
        .padding(.horizontal, 24)
        .padding(.top, NovaOB.padTop(60))
        .padding(.bottom, 12)
        .background(NovaOB.surface)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.question.title)
                .font(NovaOB.font(28, 700))
                .tracking(-0.3)
                .lineSpacing(NovaOB.lineSpacing(28, 1.2))
                .fixedSize(horizontal: false, vertical: true)
            if !controller.question.desc.isEmpty {
                Text(controller.question.desc)
                    .font(NovaOB.font(15.5))
                    .foregroundColor(NovaOB.muted)
                    .lineSpacing(NovaOB.lineSpacing(15.5, 1.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var answerWidget: some View {
        switch controller.question.kind {
        case .text: nameWidget
        case .single, .multi: NovaOBChoiceWidget(controller: controller)
        case .slider: NovaOBExperienceWidget(controller: controller)
        case .counter: NovaOBCounterWidget(controller: controller)
        }
    }

    // MARK: name

    private var nameWidget: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Adın veya tercih ettiğin isim", text: Binding(
                get: { controller.answers.name },
                set: { controller.answers.name = $0; controller.unskip("name") }
            ))
            .textContentType(.givenName)
            .focused($focused)
            .novaOBField(height: 60, radius: 18, border: focused ? NovaOB.ink : NovaOB.line, fontSize: 18)

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ÖNİZLEME")
                        .font(NovaOB.font(12))
                        .tracking(1.2)
                        .foregroundColor(NovaOB.ink)
                    Text(controller.answers.name.novaTrimmed.isEmpty
                         ? "Merhaba" : "Merhaba, \(controller.answers.name.novaTrimmed)")
                        .font(NovaOB.font(20, 600))
                        .foregroundColor(NovaOB.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NovaOB.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Image("NovaOBMascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 61)
                    .offset(x: 16, y: -54)
                    .allowsHitTesting(false)
            }
            .padding(.top, 64)
            .padding(.bottom, 20)
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 6) {
            NovaOBPrimaryButton(title: controller.primaryLabel, enabled: controller.canContinue) {
                focused = false
                controller.next()
            }
            if controller.question.skippable {
                Button { focused = false; controller.skipQuestion() } label: {
                    Text("Şimdilik geç")
                        .font(NovaOB.font(15))
                        .foregroundColor(NovaOB.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, NovaOB.padBottom(34))
        .background(NovaOB.surface)
    }
}

// MARK: - Choice widget (single + multi, list + grid)

struct NovaOBChoiceWidget: View {
    @ObservedObject var controller: NovaOBController

    private var gridOptions: [NovaOBOption] {
        controller.question.grid ? controller.visibleOptions.filter { !$0.small } : []
    }

    private var rowOptions: [NovaOBOption] {
        controller.question.grid ? controller.visibleOptions.filter(\.small) : controller.visibleOptions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.question.searchable {
                TextField("Sektör ara", text: $controller.search)
                    .autocorrectionDisabled()
                    .novaOBField(height: 42, fontSize: 16)
            }
            if !controller.selectionNote.isEmpty {
                Text(controller.selectionNote)
                    .font(NovaOB.font(13.5))
                    .foregroundColor(NovaOB.ink)
            }
            if !gridOptions.isEmpty {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 6),
                        count: controller.question.gridColumns
                    ),
                    spacing: 6
                ) {
                    ForEach(gridOptions) { option in
                        gridCell(option)
                    }
                }
            }
            ForEach(rowOptions) { option in
                listRow(option)
            }
            if controller.showsOtherField {
                TextField("Kısaca yazabilirsin", text: Binding(
                    get: { controller.answers.other(controller.question.id) },
                    set: { controller.answers.setOther(controller.question.id, $0) }
                ))
                .novaOBField(height: 52, border: NovaOB.ink, fontSize: 16)
            }
        }
    }

    private func gridCell(_ option: NovaOBOption) -> some View {
        let selected = controller.isSelected(option.value)
        return Button { toggle(option) } label: {
            VStack(alignment: .leading, spacing: 3) {
                NovaOBIconPath(path: option.icon, size: 23, color: NovaOB.ink, lineWidth: 1.6)
                Text(option.label)
                    .font(NovaOB.font(14, 600))
                    .foregroundColor(NovaOB.ink)
                    .lineSpacing(NovaOB.lineSpacing(14, 1.2))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 20)
                if !option.sub.isEmpty {
                    Text(option.sub)
                        .font(NovaOB.font(12))
                        .foregroundColor(NovaOB.muted)
                        .lineSpacing(NovaOB.lineSpacing(11, 1.25))
                }
                if controller.isSuggested(option) {
                    Text("Sana uygun olabilir").font(NovaOB.font(11.5)).foregroundColor(NovaOB.ink)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(selected ? NovaOB.fill : NovaOB.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? NovaOB.ink : NovaOB.line, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                mark(selected: selected, size: 18, check: 12)
                    .padding(8)
            }
            .opacity(controller.isBlocked(option.value) ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func listRow(_ option: NovaOBOption) -> some View {
        let selected = controller.isSelected(option.value)
        return Button { toggle(option) } label: {
            HStack(spacing: 12) {
                NovaOBIconPath(path: option.icon, size: 30, color: NovaOB.ink, lineWidth: 1.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(NovaOB.font(17, 600))
                        .foregroundColor(NovaOB.ink)
                        .lineSpacing(NovaOB.lineSpacing(17, 1.25))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !option.sub.isEmpty {
                        Text(option.sub)
                            .font(NovaOB.font(13.5))
                            .foregroundColor(NovaOB.muted)
                            .lineSpacing(NovaOB.lineSpacing(12.5, 1.3))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if controller.isSuggested(option) {
                        Text("Sana uygun olabilir").font(NovaOB.font(12)).foregroundColor(NovaOB.ink)
                    }
                }
                Spacer(minLength: 0)
                mark(selected: selected, size: 24, check: 15)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(selected ? NovaOB.fill : NovaOB.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? NovaOB.ink : NovaOB.line, lineWidth: 1.5)
            )
            .opacity(controller.isBlocked(option.value) ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func mark(selected: Bool, size: CGFloat, check: CGFloat) -> some View {
        let radius: CGFloat = controller.question.kind == .multi ? (size == 18 ? 8 : 8) : size / 2
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(selected ? NovaOB.ink : NovaOB.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? NovaOB.ink : NovaOB.line2, lineWidth: 1.5)
            )
            .frame(width: size, height: size)
            .overlay {
                if selected {
                    NovaOBIconPath(path: "M2 7.5l3.4 3.4L12 3.5", size: check, color: .white,
                                   lineWidth: 2.2, viewBox: 14)
                }
            }
    }

    private func toggle(_ option: NovaOBOption) {
        if controller.question.kind == .single {
            controller.pickSingle(option.value)
        } else {
            controller.toggleMulti(option.value)
        }
    }
}

// MARK: - Experience slider

struct NovaOBExperienceWidget: View {
    @ObservedObject var controller: NovaOBController
    @State private var dragPosition: Double?

    private var position: Double {
        if let dragPosition { return dragPosition }
        guard let exp = controller.answers.exp else { return 0 }
        return Double(exp) / 3
    }

    private var liveIndex: Int? {
        if let dragPosition { return Int((dragPosition * 3).rounded()) }
        return controller.answers.exp
    }

    private var tint: Color {
        if controller.answers.expLess { return NovaOB.ink }
        guard let liveIndex else { return NovaOB.line2 }
        return NovaOB.stopTint[liveIndex]
    }

    var body: some View {
        VStack(spacing: 22) {
            card
            lessThanYearRow
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DENEYİM ARALIĞIN")
                    .font(NovaOB.font(12))
                    .tracking(1.2)
                    .foregroundColor(NovaOB.muted)
                Text(valueLabel)
                    .font(NovaOB.font(34, 700))
                    .tracking(-0.8)
                    .foregroundColor(controller.answers.expLess ? NovaOB.ink
                                     : (liveIndex == nil ? NovaOB.disabled : NovaOB.stopTint[liveIndex ?? 0]))
                Text(valueSub)
                    .font(NovaOB.font(14))
                    .foregroundColor(NovaOB.muted)
                    .frame(minHeight: 20, alignment: .leading)
            }
            track
            HStack {
                ForEach(["1", "3", "7", "10+"], id: \.self) { label in
                    Text(label)
                        .font(NovaOB.font(12.5))
                        .monospacedDigit()
                        .foregroundColor(NovaOB.muted)
                    if label != "10+" { Spacer(minLength: 0) }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(NovaOB.line, lineWidth: 1.5)
        )
    }

    private var track: some View {
        GeometryReader { proxy in
            let available = max(1, proxy.size.width - 16)
            ZStack(alignment: .leading) {
                Capsule().fill(NovaOB.fill)
                    .frame(height: 8)
                    .padding(.horizontal, 8)
                Capsule().fill(tint)
                    .frame(width: position * available, height: 8)
                    .offset(x: 8)
                ForEach(0..<4, id: \.self) { index in
                    let reached = !controller.answers.expLess && liveIndex != nil && index <= (liveIndex ?? -1)
                    Circle()
                        .fill(reached ? Color.white : NovaOB.stopTint[index])
                        .frame(width: 10, height: 10)
                        .frame(width: 44, height: 56)
                        .contentShape(Rectangle())
                        .offset(x: 8 + CGFloat(index) / 3 * available - 22)
                        .onTapGesture { controller.pickStop(index) }
                }
                Circle()
                    .fill(NovaOB.surface)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                    .frame(width: 32, height: 32)
                    .shadow(color: Color(hex: 0x1C292E).opacity(0.18), radius: 6, y: 4)
                    .offset(x: 8 + position * available - 16)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragPosition = min(1, max(0, (value.location.x - 8) / available))
                    }
                    .onEnded { value in
                        let ratio = min(1, max(0, (value.location.x - 8) / available))
                        dragPosition = nil
                        controller.pickStop(Int((ratio * 3).rounded()))
                    }
            )
        }
        .frame(height: 56)
    }

    private var lessThanYearRow: some View {
        Button { controller.toggleLessThanYear() } label: {
            HStack(spacing: 14) {
                Text("1 yıldan az").font(NovaOB.font(16.5, 600)).foregroundColor(NovaOB.ink)
                Spacer(minLength: 0)
                Circle()
                    .fill(controller.answers.expLess ? NovaOB.ink : NovaOB.surface)
                    .overlay(Circle().strokeBorder(controller.answers.expLess ? NovaOB.ink : NovaOB.line2, lineWidth: 1.5))
                    .frame(width: 26, height: 26)
                    .overlay {
                        if controller.answers.expLess {
                            NovaOBIconPath(path: "M2 7.5l3.4 3.4L12 3.5", size: 14, color: .white,
                                           lineWidth: 2.2, viewBox: 14)
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(controller.answers.expLess ? NovaOB.fill : NovaOB.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(controller.answers.expLess ? NovaOB.ink : NovaOB.line, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var valueLabel: String {
        if controller.answers.expLess { return "1 yıldan az" }
        guard let liveIndex else { return "Henüz seçilmedi" }
        return NovaOBCatalogue.experienceStops[liveIndex].label
    }

    private var valueSub: String {
        if controller.answers.expLess { return "Mesleğe yeni başladın" }
        guard let liveIndex else { return "Sürükle veya bir durağa dokun" }
        return NovaOBCatalogue.experienceStops[liveIndex].sub
    }
}

// MARK: - Inspection counter

struct NovaOBCounterWidget: View {
    @ObservedObject var controller: NovaOBController
    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 16) {
                HStack(spacing: 18) {
                    stepButton(
                        path: "M4 10h12",
                        border: controller.answers.inspections == 0 ? Color(hex: 0xDCDCDC) : NovaOB.ink,
                        color: controller.answers.inspections == 0 ? Color(hex: 0xC4C4C4) : NovaOB.ink,
                        opacity: controller.answers.inspections == 0 ? 0.6 : 1
                    ) { controller.bumpInspections(-1) }

                    if editing {
                        TextField("", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(NovaOB.font(56, 700))
                            .foregroundColor(NovaOB.ink)
                            .tint(NovaOB.ink)
                            .focused($focused)
                            .frame(width: 120, height: 72)
                            .overlay(alignment: .bottom) { Rectangle().fill(NovaOB.ink).frame(height: 2) }
                            .onChange(of: text) { value in
                                let digits = value.filter(\.isNumber)
                                controller.answers.inspections = min(999, Int(digits) ?? 0)
                                controller.unskip("inspections")
                            }
                            .onSubmit { editing = false }
                    } else {
                        Text(String(controller.answers.inspections))
                            .font(NovaOB.font(62, 700))
                            .tracking(-2)
                            .monospacedDigit()
                            .foregroundColor(controller.skipped.contains("inspections") ? NovaOB.disabled : NovaOB.ink)
                            .frame(minWidth: 120)
                            .onTapGesture {
                                text = String(controller.answers.inspections)
                                editing = true
                                focused = true
                            }
                    }

                    stepButton(path: "M10 4v12M4 10h12", border: NovaOB.ink, color: NovaOB.ink, opacity: 1) {
                        controller.bumpInspections(1)
                    }
                }
                Text(controller.answers.inspections == 0
                     ? "Henüz teftiş deneyimim olmadı"
                     : "Son 1 yılda \(controller.answers.inspections) teftiş")
                    .font(NovaOB.font(15))
                    .foregroundColor(NovaOB.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NovaOB.line, lineWidth: 1.5)
            )

            Text("Sayıya dokunarak doğrudan yazabilirsin. “0” da geçerli bir yanıttır.")
                .font(NovaOB.font(13))
                .foregroundColor(NovaOB.muted)
                .lineSpacing(NovaOB.lineSpacing(13, 1.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: focused) { isFocused in
            if !isFocused { editing = false }
        }
    }

    private func stepButton(
        path: String, border: Color, color: Color, opacity: Double, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            NovaOBIconPath(path: path, size: 20, color: color, lineWidth: 2.2, viewBox: 20)
                .frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(border, lineWidth: 1.5))
                .opacity(opacity)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
#endif
