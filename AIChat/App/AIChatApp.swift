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
                LiveRoot(container: container)
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
    }

    @State private var phase = Phase.loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                Color.appBackground.ignoresSafeArea()
            case .ready:
                // Временная заглушка: экраны по Figma появятся в разделах 5–6 плана.
                Text("AI Chat")
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground.ignoresSafeArea())
            case .failed:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text("Couldn't open chat history")
                        .font(.headline)
                    Text("Please restart the app.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground.ignoresSafeArea())
            }
        }
        .task {
            guard case .loading = phase else { return }
            do {
                phase = .ready(try await container.makeDependencies())
            } catch {
                phase = .failed
            }
        }
    }
}
