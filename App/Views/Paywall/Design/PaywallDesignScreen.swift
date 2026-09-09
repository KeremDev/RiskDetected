import SwiftUI

struct PaywallDesignPlanOption: Equatable {
    var title: String
    var price: String
    var caption: String
    var trialNote: String?
    var badgeLabel: String?
    var badgeDiscount: String?
}

struct PaywallDesignCTAState: Equatable {
    var title: String
    var purchaseDisclosure: String?
    var isLoading: Bool
    var isDisabled: Bool
    var accessibilityIdentifier: String
}

struct PaywallDesignCrossSell: Equatable {
    enum Style: Equatable { case pro, plus }
    var style: Style
    var prefix: String
    var highlight: String
    var suffix: String
    var accessibilityIdentifier: String
}

/// Native implementation of Paywall.dc.html. Store data and purchase actions stay
/// in PaywallDesignFlowView; the same screen serves onboarding and in-app entry.
struct PaywallDesignScreen: View {
    var screen: InAppPaywallScreen
    var annual: PaywallDesignPlanOption
    var monthly: PaywallDesignPlanOption
    var selectedBilling: InAppPaywallBilling
    var cta: PaywallDesignCTAState
    var notice: String?
    var errorMessage: String?
    var crossSell: PaywallDesignCrossSell?
    var onClose: () -> Void
    var onSelectBilling: (InAppPaywallBilling) -> Void
    var onCTA: () -> Void
    var onRestore: () -> Void
    var onTerms: () -> Void
    var onPrivacy: () -> Void
    var onManageSubscription: () -> Void
    var onCrossSell: () -> Void

    @State private var showsComparison = false

    private var accent: Color { screen == .plus ? DarkPaywallStyle.gold : DarkPaywallStyle.green }
    private var tier: String { screen == .plus ? "PLUS" : "PRO" }
    private var hasTrial: Bool {
        selectedBilling == .yearly && annual.trialNote != nil && cta.purchaseDisclosure != nil
    }

    var body: some View {
        RDAdaptiveContainer { profile in
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, profile.horizontalPadding)
                // The inner GeometryReader receives the remaining space AFTER the
                // footer inset. On larger phones the plans rest above the footer;
                // on short screens or large text all content remains scrollable.
                GeometryReader { available in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            introduction(compact: profile.usesCompactPaywallLayout)
                            Spacer(minLength: profile.usesCompactPaywallLayout ? 8 : 16)
                            VStack(spacing: 10) {
                                DarkPaywallPlanRow(option: annual, selected: selectedBilling == .yearly,
                                                   compact: profile.usesCompactPaywallLayout,
                                                   identifier: "in_app_paywall.plan.yearly") {
                                    onSelectBilling(.yearly)
                                }
                                DarkPaywallPlanRow(option: monthly, selected: selectedBilling == .monthly,
                                                   compact: profile.usesCompactPaywallLayout,
                                                   identifier: "in_app_paywall.plan.monthly") {
                                    onSelectBilling(.monthly)
                                }
                                if let crossSell { crossSellCard(crossSell) }
                            }
                            .disabled(cta.isLoading)
                        }
                        .padding(.horizontal, profile.horizontalPadding)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                        .frame(minHeight: available.size.height, alignment: .top)
                    }
                    .id(screen)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer.padding(.horizontal, profile.horizontalPadding)
                    .background(Color.black)
                    // Reclaim part of the bottom inset without moving link hit areas
                    // into the home-indicator region.
                    .padding(.bottom, -min(profile.safeAreaInsets.bottom, 18))
            }
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsComparison) {
            DarkPaywallComparisonSheet()
                .preferredColorScheme(.dark)
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(screen == .plus ? "in_app_paywall.plus" : "in_app_paywall.pro")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DarkPaywallStyle.secondary)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(cta.isLoading)
            .accessibilityLabel(DarkPaywallStyle.copy("close"))
            .accessibilityIdentifier("in_app_paywall.close")
            Spacer(minLength: 0)
            Label(tier, systemImage: screen == .plus ? "crown.fill" : "star.fill")
                .modifier(DarkPaywallFont(size: 11.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(accent)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func introduction(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            DarkPaywallAvatars(compact: compact)
            Image("PaywallUsersBadge")
                .resizable().scaledToFit()
                .frame(width: compact ? 200 : 220)
                .blendMode(.screen)
                .accessibilityLabel(DarkPaywallStyle.copy("users"))
            Text(DarkPaywallStyle.copy(screen == .plus ? "plus.headline" : "pro.headline"))
                .modifier(DarkPaywallFont(size: compact ? 28 : 30, weight: .heavy))
                .tracking(-0.7)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("in_app_paywall.headline")
            VStack(alignment: .center, spacing: compact ? 6 : 7) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                        Text(feature)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .modifier(DarkPaywallFont(size: 13, weight: .regular))
                    .foregroundStyle(DarkPaywallStyle.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Button { showsComparison = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle").accessibilityHidden(true)
                    Text(DarkPaywallStyle.copy("compare")).underline()
                }
                    .modifier(DarkPaywallFont(size: 12.5, weight: .semibold))
                    .foregroundStyle(DarkPaywallStyle.secondary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("in_app_paywall.compare")
        }
        .frame(maxWidth: .infinity)
    }

    private var features: [String] {
        let prefix = screen == .plus ? "plus.feature." : "pro.feature."
        return (1...4).map { DarkPaywallStyle.copy(prefix + String($0)) }
    }

    private func crossSellCard(_ cross: PaywallDesignCrossSell) -> some View {
        let color = cross.style == .pro ? DarkPaywallStyle.green : DarkPaywallStyle.gold
        return Button(action: onCrossSell) {
            HStack(spacing: 10) {
                Image(systemName: cross.style == .pro ? "star.fill" : "crown.fill")
                    .font(.system(size: 13)).foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                Text(cross.prefix + cross.highlight + cross.suffix)
                    .modifier(DarkPaywallFont(size: 12.5, weight: .semibold))
                    .foregroundStyle(DarkPaywallStyle.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.system(size: 13))
                    .foregroundStyle(DarkPaywallStyle.secondary)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.22), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(cross.accessibilityIdentifier)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            if let message = errorMessage ?? notice {
                Text(message)
                    .modifier(DarkPaywallFont(size: 12, weight: .medium))
                    .foregroundStyle(errorMessage == nil ? DarkPaywallStyle.primary : Color(red: 1, green: 0.55, blue: 0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
            if hasTrial {
                Text(DarkPaywallStyle.copy("no_charge"))
                    .modifier(DarkPaywallFont(size: 11, weight: .bold))
                    .foregroundStyle(DarkPaywallStyle.green)
                    .accessibilityIdentifier("in_app_paywall.no_charge")
            }
            Button(action: onCTA) {
                HStack(spacing: 8) {
                    if cta.isLoading { ProgressView().tint(.black) }
                    Text(cta.title)
                        .modifier(DarkPaywallFont(size: 17, weight: .bold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if !cta.isLoading { Image(systemName: "arrow.right").font(.system(size: 15, weight: .semibold)) }
                }
                .foregroundStyle(cta.isDisabled ? Color.white.opacity(0.5) : Color.black)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(cta.isDisabled ? Color.white.opacity(0.12) : DarkPaywallStyle.cream,
                            in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).disabled(cta.isDisabled)
            .accessibilityIdentifier(cta.accessibilityIdentifier)
            if let disclosure = cta.purchaseDisclosure {
                Text(disclosure)
                    .modifier(DarkPaywallFont(size: 10.5, weight: .medium))
                    .foregroundStyle(DarkPaywallStyle.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("in_app_paywall.purchase_disclosure")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { legalButtons }
                VStack(spacing: 0) { legalButtons }
            }
            .disabled(cta.isLoading)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }

    @ViewBuilder private var legalButtons: some View {
        legalLink("privacy", onPrivacy)
        legalLink("terms", onTerms)
        legalLink("restore", onRestore)
        legalLink("manage", onManageSubscription)
    }

    private func legalLink(_ key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(RDLocalization.string("paywall.design.footer.\(key)", table: .paywall, fallback: key))
                .modifier(DarkPaywallFont(size: 10.5, weight: .medium))
                .foregroundStyle(DarkPaywallStyle.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("in_app_paywall.\(key)")
    }
}

private enum DarkPaywallStyle {
    static let cream = Color(hex: "F5F2EA")
    static let gold = Color(hex: "F5A524")
    static let green = Color(hex: "22C55E")
    static let primary = Color(hex: "EBEBF5").opacity(0.86)
    static let secondary = Color(hex: "EBEBF5").opacity(0.6)
    static func copy(_ key: String) -> String {
        RDLocalization.string("paywall.dark.\(key)", table: .paywall, fallback: key)
    }
}

/// The supplied design uses the native iOS font, with Dynamic Type preserved.
private struct DarkPaywallFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }
    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

private struct DarkPaywallAvatars: View {
    var compact: Bool
    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: -22) {
                ForEach(1...4, id: \.self) { i in avatar("PaywallJoinAvatarBack\(i)", size: 48) }
            }.opacity(0.4).blur(radius: 0.3)
            HStack(spacing: -14) {
                ForEach(1...4, id: \.self) { i in avatar("PaywallJoinAvatar\(i)", size: compact ? 60 : 66) }
            }.padding(.top, 9)
                .overlay(alignment: .bottom) {
                    Text(DarkPaywallStyle.copy("join"))
                        .modifier(DarkPaywallFont(size: 11, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                        .offset(y: 11)
                }
        }.padding(.bottom, 11)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DarkPaywallStyle.copy("join"))
    }
    private func avatar(_ name: String, size: CGFloat) -> some View {
        Image(name).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
    }
}

private struct DarkPaywallPlanRow: View {
    var option: PaywallDesignPlanOption
    var selected: Bool
    var compact: Bool
    var identifier: String
    var action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selected ? DarkPaywallStyle.cream : Color.white.opacity(0.3))
                AnyLayout(dynamicTypeSize.isAccessibilitySize
                          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                          : AnyLayout(HStackLayout(spacing: 8))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.title).modifier(DarkPaywallFont(size: 16, weight: .bold))
                        if let note = option.trialNote {
                            Text(note).modifier(DarkPaywallFont(size: 11.5, weight: .medium))
                                .foregroundStyle(DarkPaywallStyle.green)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                        Text(option.price).modifier(DarkPaywallFont(size: 15, weight: .bold))
                        Text(option.caption).modifier(DarkPaywallFont(size: 11, weight: .medium))
                            .foregroundStyle(DarkPaywallStyle.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16).padding(.vertical, compact ? 12 : 15)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? DarkPaywallStyle.cream.opacity(0.08) : Color.white.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(selected ? DarkPaywallStyle.cream : Color.white.opacity(0.13), lineWidth: 1.5))
            .overlay(alignment: .top) {
                if let discount = option.badgeDiscount {
                    Text(discount).modifier(DarkPaywallFont(size: 10.5, weight: .heavy))
                        .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 3)
                        .background(DarkPaywallStyle.green, in: Capsule()).offset(y: -10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge = option.badgeLabel {
                    Text(badge).modifier(DarkPaywallFont(size: 8, weight: .heavy))
                        .foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(DarkPaywallStyle.gold, in: RoundedRectangle(cornerRadius: 5))
                        .padding(.trailing, 12).offset(y: -6)
                }
            }
            .padding(.top, option.badgeLabel == nil ? 0 : 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue([option.price, option.caption, option.trialNote].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Reuses the live application's comparison data, not the mock's sample quotas.
private struct DarkPaywallComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 520
    private var rows: [(String, PaywallDesignMark, PaywallDesignMark, PaywallDesignMark)] {
        let plus = PaywallDesignCopy.freeVersusPlusRows
        let pro = PaywallDesignCopy.plusVersusProRows
        let premiumSections: [(String, PaywallDesignMark, PaywallDesignMark, PaywallDesignMark)] = [
            (DarkPaywallStyle.copy("expert"), .cross, .check(.green), .check(.green)),
            (DarkPaywallStyle.copy("training"), .cross, .check(.green), .check(.green)),
            (DarkPaywallStyle.copy("notebook"), .cross, .check(.green), .check(.green)),
            (DarkPaywallStyle.copy("reports"), .cross, .check(.green), .check(.green)),
        ]
        return plus.map { row in
            (row.title, row.left, row.right, pro.first { $0.title == row.title }?.right ?? row.right)
        } + pro.filter { proRow in !plus.contains { $0.title == proRow.title } }.map {
            ($0.title, .cross, $0.left, $0.right)
        } + premiumSections
    }
    var body: some View {
        RDAdaptiveContainer { _ in
            ScrollView {
                VStack(spacing: 4) {
                    Label(DarkPaywallStyle.copy("compare"), systemImage: "list.bullet.rectangle")
                        .modifier(DarkPaywallFont(size: 17, weight: .heavy))
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack(spacing: 6) {
                            Text(DarkPaywallStyle.copy("feature"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("FREE").frame(width: 52)
                            Text("PLUS").foregroundStyle(DarkPaywallStyle.gold).frame(width: 52)
                            Text("PRO").foregroundStyle(DarkPaywallStyle.green).frame(width: 52)
                        }.modifier(DarkPaywallFont(size: 10.5, weight: .bold))
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(row.0).modifier(DarkPaywallFont(size: 13, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                            AnyLayout(dynamicTypeSize.isAccessibilitySize
                                      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                      : AnyLayout(HStackLayout(spacing: 10))) {
                                value(row.1, title: "FREE", color: DarkPaywallStyle.secondary)
                                value(row.2, title: "PLUS", color: DarkPaywallStyle.gold)
                                value(row.3, title: "PRO", color: DarkPaywallStyle.green)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
                        } else {
                            HStack(spacing: 6) {
                                Text(row.0).modifier(DarkPaywallFont(size: 12.5, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                mark(row.1).foregroundStyle(DarkPaywallStyle.secondary).frame(width: 52)
                                mark(row.2).foregroundStyle(DarkPaywallStyle.green).frame(width: 52)
                                mark(row.3).foregroundStyle(DarkPaywallStyle.green).frame(width: 52)
                            }.padding(.vertical, 5)
                                .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
                        }
                    }
                Button { dismiss() } label: {
                    Text(DarkPaywallStyle.copy("close"))
                        .modifier(DarkPaywallFont(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).padding(.top, 6)
                    .accessibilityIdentifier("in_app_paywall.compare.close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 0)
                .background {
                    GeometryReader { content in
                        Color.clear.preference(key: DarkPaywallComparisonHeightKey.self,
                                               value: content.size.height)
                    }
                }
            }
        }.foregroundStyle(.white).background(Color(hex: "131316").ignoresSafeArea())
            .onPreferenceChange(DarkPaywallComparisonHeightKey.self) {
                if $0 > 0 { contentHeight = $0.rounded(.up) }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
    }
    private func value(_ mark: PaywallDesignMark, title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
            switch mark {
            case .cross: Image(systemName: "minus").accessibilityLabel(DarkPaywallStyle.copy("unavailable"))
            case .check: Image(systemName: "checkmark").accessibilityLabel(DarkPaywallStyle.copy("included"))
            case let .text(text, _): Text(text)
            }
        }.modifier(DarkPaywallFont(size: 11, weight: .bold))
            .foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private func mark(_ value: PaywallDesignMark) -> some View {
        Group {
            switch value {
            case .cross: Image(systemName: "minus").accessibilityLabel(DarkPaywallStyle.copy("unavailable"))
            case .check: Image(systemName: "checkmark").accessibilityLabel(DarkPaywallStyle.copy("included"))
            case let .text(text, _): Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }.modifier(DarkPaywallFont(size: 11, weight: .bold))
    }
}

private struct DarkPaywallComparisonHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
