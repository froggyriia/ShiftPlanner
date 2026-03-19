import SwiftUI

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentIndex = 0

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            title: "Добро пожаловать в Shift Planner",
            subtitle: "Простой способ организовать смены для кафе, ресторанов и других заведений.",
            systemImage: "calendar.badge.clock",
            accentColor: .blue
        ),
        OnboardingSlide(
            title: "Менеджер создаёт расписание",
            subtitle: "Добавляйте должности, задавайте правила для смен и автоматически формируйте график на месяц.",
            systemImage: "person.2.badge.gearshape",
            accentColor: .purple
        ),
        OnboardingSlide(
            title: "Сотрудники отмечают свою доступность",
            subtitle: "Присоединяйтесь по коду, отмечайте дни, когда можете работать, и просматривайте свои смены.",
            systemImage: "checkmark.circle.badge.clock",
            accentColor: .green
        )
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                topBar
                slideCard
                pageIndicators
                bottomButtons
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()

            if currentIndex < slides.count - 1 {
                Button("Пропустить") {
                    hasSeenOnboarding = true
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
    }

    private var slideCard: some View {
        let slide = slides[currentIndex]

        return VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(slide.accentColor.opacity(0.12))
                    .frame(width: 160, height: 160)

                Image(systemName: slide.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundColor(slide.accentColor)
            }

            VStack(spacing: 14) {
                Text(slide.title)
                    .font(.system(size: 30, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(slide.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 540)
        .padding(.horizontal, 20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
        .animation(.easeInOut, value: currentIndex)
    }

    private var pageIndicators: some View {
        HStack(spacing: 8) {
            ForEach(0..<slides.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? slides[currentIndex].accentColor : Color(.systemGray4))
                    .frame(width: index == currentIndex ? 26 : 8, height: 8)
                    .animation(.easeInOut, value: currentIndex)
            }
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button {
                if currentIndex < slides.count - 1 {
                    withAnimation {
                        currentIndex += 1
                    }
                } else {
                    hasSeenOnboarding = true
                }
            } label: {
                Text(currentIndex == slides.count - 1 ? "Начать" : "Далее")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(slides[currentIndex].accentColor)
            .controlSize(.large)

            if currentIndex > 0 {
                Button("Назад") {
                    withAnimation {
                        currentIndex -= 1
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
