import SwiftUI

/// Главный экран (макеты «Main Page — Free User / Premium User»): история, PRO, настройки,
/// поле «Ask anything…» (открывает чат) и карточка генерации видео.
struct MainView: View {
    @StateObject private var model: MainViewModel
    @EnvironmentObject private var router: AppRouter

    init(subscription: any SubscriptionService) {
        _model = StateObject(wrappedValue: MainViewModel(subscription: subscription))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                ScrollView {
                VStack(spacing: 40) {
                    VStack(spacing: 24) {
                        Image("IconSparklesLarge")
                            .frame(width: 60, height: 60)
                            .accessibilityHidden(true)
                        Text("Your AI tools,\nready to go")
                            .font(AppFont.title)
                            .tracking(0.4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.appAccent)
                        askField
                    }
                    VideoGeneratorCard { router.push(.templates) }
                }
                .padding(.horizontal, AppMetrics.sideInset)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                // Как в макете: блок по центру свободной высоты; на маленьких экранах — прокрутка.
                .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehaviorIfAvailable()
            }
        }
        .background(GlowBackground())
        .task { await model.observeSubscription() }
    }

    private var header: some View {
        HStack {
            CircleIconButton(label: "History") {
                router.push(.history(.chat))
            } icon: {
                HistoryIcon()
            }
            Spacer()
            if model.showsProButton {
                ProButton { router.showPaywall(from: .proButton) }
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            CircleIconButton(label: "Settings") {
                router.push(.settings)
            } icon: {
                Image("IconSettings")
                    .renderingMode(.template)
                    .foregroundStyle(Color.appAccent)
            }
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .padding(.vertical, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.showsProButton)
    }

    /// Поле-кнопка: открывает новый чат (заметка к макету).
    private var askField: some View {
        Button {
            router.push(.chat(chatId: nil, prompt: nil))
        } label: {
            HStack(spacing: 16) {
                Image("IconSparkles")
                    .frame(width: 24, height: 24)
                Text("Ask anything...")
                    .font(AppFont.body)
                    .foregroundStyle(Color.appAccent.opacity(0.5))
                Spacer()
            }
            .padding(16)
            .background(Color.appSurface.opacity(0.7), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius)
                    .strokeBorder(
                        LinearGradient(colors: [.appGradientStart.opacity(0.6), .appGradientEnd.opacity(0.3)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Круглая кнопка 40pt на подложке 8% белого (история, настройки).
struct CircleIconButton<Icon: View>: View {
    let label: LocalizedStringKey
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 24, height: 24)
                .frame(width: 40, height: 40)
                .background(Color.appFillTertiary, in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Иконка «история» из макета (Iconex Time Circle): круг и стрелки часов.
private struct HistoryIcon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("IconHistoryCircle")
                .renderingMode(.template)
                .offset(x: 1.25, y: 1.25)
            Image("IconHistoryHands")
                .renderingMode(.template)
                .offset(x: 11.25, y: 7.25)
        }
        .foregroundStyle(Color.appAccent)
        .frame(width: 24, height: 24, alignment: .topLeading)
    }
}

/// Кнопка PRO — только без подписки, ведёт на пейвол.
private struct ProButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image("IconSparkleSmall")
                    .frame(width: 14, height: 14)
                Text("PRO")
                    .font(AppFont.subheadline.weight(.semibold))
                    .tracking(0.56)
                    .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(AppGradient.primary, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Карточка «Turn Photo into Video» — вход в генератор видео.
struct VideoGeneratorCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image("IconImageToImageWhite")
                    .frame(width: 20, height: 20)
                    .padding(8)
                    .background(Color.white.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn Photo\ninto Video")
                        .font(AppFont.title3Medium)
                        .foregroundStyle(Color.appAccent)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        Text("Animate")
                        Circle().frame(width: 4, height: 4)
                        Text("Templates")
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.appAccent)
                    .opacity(0.7)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 189, alignment: .topLeading)
            .background(alignment: .topLeading) { background }
            .overlay(alignment: .topTrailing) { readyBadge }
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.appGradientStart.opacity(0.8), .appGradientEnd.opacity(0.8)],
                           startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
            Image("VideoCardArt")
                .resizable()
                .scaledToFill()
                .frame(width: 240, height: 360)
                .opacity(0.5)
                .offset(x: 132, y: -69)
                .accessibilityHidden(true)
        }
    }

    private var readyBadge: some View {
        HStack(spacing: 8) {
            Text("Ready in seconds")
                .font(AppFont.caption)
                .tracking(0.06)
            Image(systemName: "play.fill")
                .font(.system(size: 11))
        }
        .foregroundStyle(Color.appAccent)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.white.opacity(0.3), in: Capsule())
        .padding(20)
    }
}

#if DEBUG
#Preview("Free") {
    NavigationStack {
        MainView(subscription: FakeSubscriptionService(isPremium: false))
    }
    .environmentObject(AppRouter(settings: InMemorySettingsStore(hasCompletedOnboarding: true)))
}

#Preview("Premium") {
    NavigationStack {
        MainView(subscription: FakeSubscriptionService(isPremium: true))
    }
    .environmentObject(AppRouter(settings: InMemorySettingsStore(hasCompletedOnboarding: true)))
}
#endif
