import SwiftUI

@main
struct AIChatApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var container = AppContainer(
        environment: AppContainer.environment(for: .processInfo),
        launchOptions: LaunchOptions(arguments: ProcessInfo.processInfo.arguments)
    )

    var body: some Scene {
        WindowGroup {
            switch container.environment {
            case .live:
                #if DEBUG
                if container.launchOptions.showComponentGallery {
                    ComponentGallery()
                } else {
                    LiveRoot(container: container)
                }
                #else
                LiveRoot(container: container)
                #endif
            case .unitTests:
                EmptyView()
            }
        }
    }
}

/// Запуск: открываем базу (асинхронно), потом показываем экраны.
private struct LiveRoot: View {
    let container: AppContainer

    private enum Phase {
        case loading
        case ready(AppDependencies)
        case failed

        var isReady: Bool {
            if case .ready = self { true } else { false }
        }
    }

    @State private var phase = Phase.loading
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch phase {
            case .loading:
                SplashView()
                    .transition(.opacity)
            case let .ready(dependencies):
                RootView(dependencies: dependencies, settings: container.settings)
                    .transition(.opacity)
                    // Сеть и запуск → outbox и незавершённые генерации; живут, пока живо окно.
                    .task { await dependencies.chat.run() }
                    .task { await dependencies.video.run() }
                    .onChange(of: scenePhase) { phase in
                        guard phase == .active else { return }
                        dependencies.chat.appDidBecomeActive()
                        dependencies.video.appDidBecomeActive()
                    }
            case .failed:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Couldn't open chat history")
                        .font(AppFont.headline)
                    Text("Please restart the app.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .foregroundStyle(Color.appAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground.ignoresSafeArea())
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase.isReady)
        .task {
            guard case .loading = phase else { return }
            // Сплэш виден хотя бы секунду — без мигания на быстром запуске.
            async let minimumSplash: Void = (try? await Task.sleep(for: .seconds(1))) ?? ()
            do {
                let dependencies = try await container.makeDependencies()
                await minimumSplash
                phase = .ready(dependencies)
            } catch {
                await minimumSplash
                phase = .failed
            }
        }
    }
}
