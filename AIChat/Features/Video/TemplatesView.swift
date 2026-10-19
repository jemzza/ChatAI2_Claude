import SwiftUI

/// Каталог шаблонов (макеты «AI Video — Templates / Categories Scroll / Templates Scrolled»):
/// шапка и строка категорий закреплены, прокручивается только сетка.
struct TemplatesView: View {
    @StateObject private var model: TemplatesViewModel
    @EnvironmentObject private var router: AppRouter
    private let thumbnails: any VideoThumbnailing

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    init(dependencies: AppDependencies) {
        _model = StateObject(wrappedValue: TemplatesViewModel(api: dependencies.videoAPI))
        thumbnails = dependencies.thumbnails
    }

    var body: some View {
        VStack(spacing: 0) {
            AvatarHeader(icon: "IconImageToImageWhite", title: "AI Video") { router.pop() }
            content
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 24) {
                categoriesPlaceholder
                grid(placeholders: 6)
            }
            .padding(.top, 24)
        case let .failed(kind):
            LoadErrorView(kind: kind) { Task { await model.load() } }
        case .loaded:
            VStack(spacing: 24) {
                categoriesRow
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.visibleTemplates) { template in
                            TemplateCard(template: template, thumbnails: thumbnails) {
                                router.push(.templatePreview(templateId: template.id,
                                                             category: model.selectedCategory?.id))
                            }
                        }
                    }
                    .padding(.horizontal, AppMetrics.sideInset)
                    .padding(.bottom, 16)
                    .animation(.easeInOut(duration: 0.25), value: model.selectedCategory)
                }
            }
            .padding(.top, 24)
        }
    }

    private var categoriesRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.categories) { category in
                        ChipButton(title: category.title, isSelected: category == model.selectedCategory,
                                   style: .filled) {
                            withAnimation(.easeInOut(duration: 0.2)) { model.selectedCategory = category }
                            withAnimation { proxy.scrollTo(category.id, anchor: .center) }
                        }
                        .id(category.id)
                    }
                }
                .padding(.horizontal, AppMetrics.sideInset)
            }
        }
    }

    private var categoriesPlaceholder: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                Capsule().fill(Color.appSurface.opacity(0.6)).frame(width: 76, height: 33)
            }
            Spacer()
        }
        .padding(.horizontal, AppMetrics.sideInset)
    }

    private func grid(placeholders: Int) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<placeholders, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppMetrics.cardRadius)
                    .fill(Color.appSurface)
                    .frame(height: 232)
                    .overlay(ProgressView().tint(.appTextSecondary))
            }
        }
        .padding(.horizontal, AppMetrics.sideInset)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Карточка шаблона: первый кадр превью, затемнение снизу, название.
struct TemplateCard: View {
    let template: VideoTemplate
    let thumbnails: any VideoThumbnailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VideoThumbnailView(url: template.previewURL, thumbnails: thumbnails)
                .frame(height: 232)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(colors: [Color.appSurface.opacity(0), Color.appSurface.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottom) {
                    // Название шаблона — из API.
                    Text(template.name)
                        .font(AppFont.body)
                        .foregroundStyle(Color.appAccent)
                        .lineLimit(1)
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
                .contentShape(RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Не загрузилось: понятный текст по виду ошибки и «Try again».
struct LoadErrorView: View {
    let kind: ErrorKind
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: kind == .offline ? "wifi.slash" : "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(AppGradient.primary)
            Text(ErrorText.key(for: MessageFailure(kind: kind)))
                .font(AppFont.body)
                .foregroundStyle(Color.appAccent.opacity(0.8))
                .multilineTextAlignment(.center)
            GradientButton(title: "Try again", action: onRetry)
                .frame(width: 200)
        }
        .padding(AppMetrics.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
