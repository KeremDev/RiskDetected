import SwiftUI

struct OBLoadingTestimonialCarousel: View {
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var carouselTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            Text(localized("onboarding.obloading.view.sahadaki.profesyoneller.ne.diyor.9bf3d77a"))
            .font(RDTypography.font(size: RDFontScale.size(compact ? 13 : 14), weight: .bold))
            .foregroundStyle(Color.rdOnyx)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compact ? 6 : 10)

            ZStack {
                testimonialCard(testimonials[index])
                    .id(testimonials[index].id)
                    .transition(
                        reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
            .frame(height: compact ? 176 : 196, alignment: .top)

            HStack(spacing: 5) {
                ForEach(testimonials.indices, id: \.self) { itemIndex in
                    Capsule(style: .continuous)
                        .fill(itemIndex == index ? Color.rdOnyx : Color.rdOnyx.opacity(0.15))
                        .frame(width: itemIndex == index ? 16 : 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.obSpring, value: index)
        }
        .onAppear(perform: startCarousel)
        .onDisappear(perform: stopCarousel)
    }

    private func startCarousel() {
        guard carouselTask == nil else { return }
        carouselTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 2_700_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .obSpring) {
                    index = (index + 1) % testimonials.count
                }
            }
        }
    }

    private func stopCarousel() {
        carouselTask?.cancel()
        carouselTask = nil
    }
}

private extension OBLoadingTestimonialCarousel {
    func testimonialCard(_ testimonial: OBLoadingTestimonial) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            HStack(spacing: 10) {
                Image(testimonial.avatarAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.rdOnyx.opacity(0.10), lineWidth: 1))

                VStack(alignment: .leading, spacing: 1) {
                    Text(testimonial.name)
                        .font(RDTypography.font(size: RDFontScale.size(compact ? 12.5 : 13.5), weight: .bold))
                        .foregroundStyle(Color.rdOnyx)

                    Text(testimonial.role)
                        .font(RDTypography.font(size: RDFontScale.size(compact ? 9.5 : 10.5), weight: .medium))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(RDTypography.font(size: RDFontScale.size(compact ? 8 : 9), weight: .regular))
                    }
                }
                .foregroundStyle(Color.rdPlanPlus)
                .accessibilityLabel(Text(verbatim: "\(5)/\(5)"))
            }

            Text(testimonial.headline)
                .font(RDTypography.font(size: RDFontScale.size(compact ? 12.5 : 13.5), weight: .bold))
                .foregroundStyle(Color.rdOnyx)
                .fixedSize(horizontal: false, vertical: true)

            Text(testimonial.body)
                .font(RDTypography.font(size: RDFontScale.size(compact ? 10.5 : 11.5), weight: .medium))
                .foregroundStyle(Color.rdSlate)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(compact ? 13 : 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.rdOnyx.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.rdOnyx.opacity(0.055), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}

private extension OBLoadingTestimonialCarousel {
    var testimonials: [OBLoadingTestimonial] {
        [
            OBLoadingTestimonial(
                id: "elif",
                avatarAsset: "OBTestimonialAvatarElif",
                name: localized("onboarding.obloading.testimonial.elif.name.e52e0716"),
                role: localized("onboarding.obloading.testimonial.elif.role.7019432c"),
                headline: localized("onboarding.obloading.testimonial.elif.headline.c1de84e8"),
                body: localized("onboarding.obloading.testimonial.elif.body.77713b0d")
            ),
            OBLoadingTestimonial(
                id: "mert",
                avatarAsset: "OBTestimonialAvatarMert",
                name: localized("onboarding.obloading.testimonial.mert.name.a7c05fb2"),
                role: localized("onboarding.obloading.testimonial.mert.role.0fdf6df8"),
                headline: localized("onboarding.obloading.testimonial.mert.headline.75a23da9"),
                body: localized("onboarding.obloading.testimonial.mert.body.c7672046")
            ),
            OBLoadingTestimonial(
                id: "selin",
                avatarAsset: "OBTestimonialAvatarSelin",
                name: localized("onboarding.obloading.testimonial.selin.name.e6db2340"),
                role: localized("onboarding.obloading.testimonial.selin.role.a69649f2"),
                headline: localized("onboarding.obloading.testimonial.selin.headline.15a94ce8"),
                body: localized("onboarding.obloading.testimonial.selin.body.d190c795")
            ),
            OBLoadingTestimonial(
                id: "burak",
                avatarAsset: "OBTestimonialAvatarBurak",
                name: localized("onboarding.obloading.testimonial.burak.name.32f1b793"),
                role: localized("onboarding.obloading.testimonial.burak.role.02596e55"),
                headline: localized("onboarding.obloading.testimonial.burak.headline.2720e7e9"),
                body: localized("onboarding.obloading.testimonial.burak.body.93b907c8")
            )
        ]
    }

    func localized(_ key: String) -> String {
        RDLocalization.string(key, table: .onboarding, fallback: key)
    }
}

private struct OBLoadingTestimonial: Identifiable {
    let id: String
    let avatarAsset: String
    let name: String
    let role: String
    let headline: String
    let body: String
}
