import PhotosUI
import SwiftUI
import UIKit

/// Генерация и результат на одном экране: состояние берётся из базы.
struct GenerationView: View {
    @StateObject private var model: GenerationViewModel
    @EnvironmentObject private var router: AppRouter
    private let photoAccess: any PhotoLibraryAccess

    @State private var isPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?

    init(id: UUID, dependencies: AppDependencies) {
        photoAccess = dependencies.photoAccess
        let video = dependencies.video
        _model = StateObject(wrappedValue: GenerationViewModel(
            id: id, repository: dependencies.videoRepository, media: dependencies.media,
            photoSaver: dependencies.photoSaver, service: video
        ) { generation, photo in
            let template = VideoTemplate(id: generation.templateId, name: generation.templateName, category: "",
                                         previewURL: nil, qualities: [], duration: nil)
            return try await video.create(template: template, photo: photo, aspect: generation.aspect,
                                          quality: generation.quality)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader(isResult ? "Result" : nil) { router.pop() }
            content
                .frame(maxHeight: .infinity)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.35), value: model.phase)
        .toast($model.toast)
        .haptic(on: model.toast, ToastMessage.haptic)
        .haptic(on: model.saveResult) { result in
            switch result {
            case .saved: Haptics.success
            case .failed: Haptics.error
            case nil: nil
            }
        }
        // Видео готово — отклик, пока пользователь на экране.
        .haptic(on: model.phase) { phase in
            if case .ready = phase { return Haptics.success }
            return nil
        }
        .task { await model.observe() }
        .onAppear {
            // Захватываем только роутер — без цикла View → StateObject → модель.
            model.onReplaced = { [router] id in router.replaceTop(with: .generation(id: id)) }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            pickerItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    model.toast = ToastMessage(kind: .failure, text: "Upload failed")
                    return
                }
                await model.replacePhoto(data)
            }
        }
        .sheet(isPresented: Binding(get: { model.shareURL != nil }, set: { if !$0 { model.shareURL = nil } })) {
            if let url = model.shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var isResult: Bool {
        if case .ready = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            Color.clear
        case .generating:
            GeneratingView()
                .transition(.opacity)
        case let .ready(url):
            result(url)
                .transition(.opacity)
        case let .failed(kind):
            LoadErrorView(kind: kind) { Task { await model.retry() } }
        case .missing:
            LoadErrorView(kind: .notFound) { router.pop() }
        }
    }

    private func result(_ url: URL) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ResultPlayer(url: url, aspect: model.aspect, isPlaying: model.isPlaying,
                         onTap: model.togglePlayback, onReplace: replace)
                .overlay { saveCard }
            HStack(spacing: 16) {
                Button {
                    Task { await model.share() }
                } label: {
                    Text("Share")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.appAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppMetrics.buttonHeight)
                        .background(Color.appSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
                }
                .buttonStyle(PressableButtonStyle())
                GradientButton(title: "Download", isLoading: model.isSaving) {
                    Task { await model.save() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var saveCard: some View {
        if let result = model.saveResult {
            SaveResultCard(result: result)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .task(id: result) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { model.saveResult = nil }
                }
        }
    }

    private func replace() {
        Task {
            if await photoAccess.requestAccess() { isPickerPresented = true }
        }
    }
}

/// «Generating…»: вращающееся градиентное кольцо (как Lottie из заметки к макету, но на SwiftUI).
private struct GeneratingView: View {
    var body: some View {
        VStack(spacing: 40) {
            GeneratingRing()
                .frame(width: 200, height: 200)
            VStack(spacing: 8) {
                Text("Generating…")
                    .font(AppFont.title3)
                    .foregroundStyle(Color.appAccent)
                Text("We’re creating the best result for you")
                    .font(AppFont.body)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .accessibilityElement(children: .combine)
    }
}

private struct GeneratingRing: View {
    @State private var isRotating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(
                AngularGradient(colors: [.appGradientEnd.opacity(0.05), .appGradientEnd.opacity(0.6), .appGradientEnd],
                                center: .center, startAngle: .degrees(0), endAngle: .degrees(260)),
                style: StrokeStyle(lineWidth: 36, lineCap: .round)
            )
            .padding(18)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isRotating)
            .onAppear { isRotating = true }
            .accessibilityHidden(true)
    }
}

/// Результат: контейнер в пропорции видео (16:9 / 9:16 / 1:1), тап — play/pause,
/// на паузе — затемнение и ▶, сверху справа — «Replace».
private struct ResultPlayer: View {
    let url: URL
    let aspect: VideoAspect
    let isPlaying: Bool
    let onTap: () -> Void
    let onReplace: () -> Void

    var body: some View {
        LoopingVideoPlayer(url: url, isPlaying: isPlaying, isMuted: false)
            .aspectRatio(aspect.ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.appSurface)
            .overlay {
                if !isPlaying {
                    ZStack {
                        Color.black.opacity(0.4)
                        Image(systemName: "play.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.appAccent)
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onReplace) {
                    HStack(spacing: 8) {
                        Image("IconRefresh").renderingMode(.template)
                        Text("Replace").font(AppFont.subheadline)
                    }
                    .foregroundStyle(Color.appAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.appSurface.opacity(0.6), in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .onTapGesture(perform: onTap)
            .animation(.easeInOut(duration: 0.2), value: isPlaying)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(isPlaying ? "Pause" : "Play"))
    }
}

/// «Video saved» / «Couldn't save video» поверх результата.
private struct SaveResultCard: View {
    let result: GenerationViewModel.SaveResult

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: result == .saved ? "checkmark" : "xmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(result == .saved ? Color.appAccent : Color.red)
                .padding(.bottom, 4)
            Text(result == .saved ? "Video saved" : "Couldn't save video")
                .font(AppFont.headline)
                .foregroundStyle(Color.appAccent)
            Text(result == .saved ? "You can find it in your Photos" : "Please try again")
                .font(AppFont.caption)
                .foregroundStyle(Color.appAccent.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color.appSurface.opacity(0.9), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        .accessibilityElement(children: .combine)
    }
}

/// Системный share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
