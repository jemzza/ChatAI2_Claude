import PhotosUI
import SwiftUI

/// Экран шаблона: карусель превью, фото пользователя, формат и качество, «Create».
struct TemplatePreviewView: View {
    @StateObject private var model: TemplatePreviewViewModel
    @EnvironmentObject private var router: AppRouter
    private let thumbnails: any VideoThumbnailing
    private let photoAccess: any PhotoLibraryAccess

    private enum Dropdown {
        case format
        case quality
    }

    @State private var dropdown: Dropdown?
    @State private var isPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?

    init(templateId: Int64, category: String?, dependencies: AppDependencies) {
        thumbnails = dependencies.thumbnails
        photoAccess = dependencies.photoAccess
        let video = dependencies.video
        _model = StateObject(wrappedValue: TemplatePreviewViewModel(
            templateId: templateId, category: category, api: dependencies.videoAPI,
            subscription: dependencies.subscription
        ) { template, photo, aspect, quality in
            try await video.create(template: template, photo: photo, aspect: aspect, quality: quality)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationHeader(title: model.currentTemplate.map { Text($0.name) }) {
                router.pop()
            }
            .animation(.none, value: model.currentIndex)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    TemplateCarousel(templates: model.templates, index: $model.currentIndex, thumbnails: thumbnails)
                        .frame(height: 311)
                        .padding(.horizontal, -AppMetrics.sideInset)
                    PhotoSlot(state: model.photo, onAdd: addPhoto, onRemove: model.removePhoto)
                    VStack(spacing: 8) {
                        OptionRow(title: "Format", value: Text(model.aspect.rawValue)) { toggle(.format) }
                            .overlay(alignment: .bottomTrailing) {
                                if dropdown == .format { formatMenu }
                            }
                            .zIndex(dropdown == .format ? 2 : 0)
                        OptionRow(title: "Quality", value: Text(model.quality.title)) { toggle(.quality) }
                            .overlay(alignment: .bottomTrailing) {
                                if dropdown == .quality { qualityMenu }
                            }
                            .zIndex(dropdown == .quality ? 2 : 0)
                    }
                    .zIndex(1)
                }
                .padding(.horizontal, AppMetrics.sideInset)
                .padding(.vertical, 16)
            }
            .scrollBounceBehaviorIfAvailable()
            GradientButton(title: "Create", isEnabled: model.canCreate, isLoading: model.isCreating) {
                Task { await model.create() }
            }
            .padding(.horizontal, AppMetrics.sideInset)
            .padding(.bottom, 16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        // Тап мимо списка закрывает его без изменений.
        .overlay {
            if dropdown != nil {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { dropdown = nil } }
                    .zIndex(0)
            }
        }
        .toast($model.toast)
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            pickerItem = nil
            Task { await model.loadPhoto { try await item.loadTransferable(type: Data.self) } }
        }
        .task { await model.load() }
        .onAppear {
            model.onPaywall = { router.showPaywall(from: .premiumAction) }
            model.onCreated = { id in router.replaceTop(with: .generation(id: id)) }
        }
    }

    private func addPhoto() {
        Task {
            // Системный запрос доступа перед галереей (макет «Photo Permission»);
            // «Don't Allow» — остаёмся на экране без изменений.
            if await photoAccess.requestAccess() { isPickerPresented = true }
        }
    }

    private func toggle(_ menu: Dropdown) {
        withAnimation(.easeOut(duration: 0.2)) { dropdown = dropdown == menu ? nil : menu }
    }

    private var formatMenu: some View {
        DropdownMenu(options: VideoAspect.allCases, selection: model.aspect) { aspect in
            HStack(spacing: 12) {
                AspectIcon(aspect: aspect, isSelected: aspect == model.aspect)
                optionText(Text(aspect.rawValue), subtitle: aspect.subtitle, isSelected: aspect == model.aspect)
            }
        } onSelect: { aspect in
            model.aspect = aspect
            withAnimation(.easeOut(duration: 0.2)) { dropdown = nil }
        }
    }

    private var qualityMenu: some View {
        DropdownMenu(options: TemplatePreviewViewModel.QualityOption.allCases, selection: model.quality) { option in
            optionText(Text(option.title), subtitle: option.subtitle, isSelected: option == model.quality)
        } onSelect: { option in
            model.quality = option
            withAnimation(.easeOut(duration: 0.2)) { dropdown = nil }
        }
    }

    private func optionText(_ title: Text, subtitle: LocalizedStringKey, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.appAccent.opacity(isSelected ? 1 : 0.85))
            Text(subtitle)
                .font(AppFont.caption)
                .foregroundStyle(Color.appAccent.opacity(0.45))
        }
    }
}

// MARK: - Части экрана

/// Карусель превью: текущая карточка по центру, соседние выглядывают; свайп листает.
/// Текущий шаблон проигрывается беззвучно по кругу, остальные — первым кадром.
private struct TemplateCarousel: View {
    let templates: [VideoTemplate]
    @Binding var index: Int
    let thumbnails: any VideoThumbnailing

    private let cardWidth: CGFloat = 331
    private let spacing: CGFloat = 16
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let step = cardWidth + spacing
            let leading = (proxy.size.width - cardWidth) / 2
            HStack(spacing: spacing) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { offset, template in
                    card(template, isCurrent: offset == index, isNear: abs(offset - index) <= 2,
                         size: CGSize(width: cardWidth, height: proxy.size.height))
                }
            }
            .offset(x: leading - CGFloat(index) * step + drag)
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation.width }
                    .onEnded { value in
                        let predicted = value.predictedEndTranslation.width
                        let delta = Int((-predicted / step).rounded())
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            index = min(max(index + max(min(delta, 1), -1), 0), max(templates.count - 1, 0))
                        }
                    }
            )
        }
        .clipped()
    }

    @ViewBuilder
    private func card(_ template: VideoTemplate, isCurrent: Bool, isNear: Bool, size: CGSize) -> some View {
        ZStack {
            if isNear {
                VideoThumbnailView(url: template.previewURL, thumbnails: thumbnails, maxPixelSize: 700)
                if isCurrent, let url = template.previewURL {
                    LoopingVideoPlayer(url: url)
                        .transition(.opacity)
                }
            } else {
                Color.appSurface
            }
        }
        // Размер — до обрезки: иначе скругляется картинка своего размера, а не карточка.
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Слот фото 100×100: «+» с градиентной обводкой → индикатор → фото с «×».
private struct PhotoSlot: View {
    let state: TemplatePreviewViewModel.PhotoState
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack {
            switch state {
            case .empty:
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 100, height: 100)
                        .background(Color.appSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppGradient.primary, lineWidth: 1))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Add photo"))
            case .loading:
                ProgressView()
                    .tint(.appGradientEnd)
                    .frame(width: 100, height: 100)
                    .background(Color.appSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(Text("Uploading photo"))
            case let .loaded(data):
                PhotoThumbnail(data: data)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .topTrailing) {
                        Button(action: onRemove) {
                            Image("IconCloseGradient")
                                .frame(width: 24, height: 24)
                                .padding(4)
                                .background(Color.white, in: Circle())
                        }
                        .offset(x: 8, y: -8)
                        .accessibilityLabel(Text("Remove photo"))
                    }
            }
        }
        .frame(width: 100, height: 100)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

/// Миниатюра выбранного фото (декодируется вне главного потока и уменьшается).
private struct PhotoThumbnail: View {
    let data: Data
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.appSurface
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .task(id: data) {
            image = await Task.detached(priority: .userInitiated) {
                ImageDownscaler.jpeg(from: data).flatMap(UIImage.init(data:))
            }.value
        }
    }
}

/// Строка «Format 16:9» / «Quality 1080p».
private struct OptionRow: View {
    let title: LocalizedStringKey
    let value: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).opacity(0.6)
                Spacer()
                value
            }
            .font(AppFont.bodyBold)
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(Color.appSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Выпадающий список из макета: карточка 220pt, выбранный пункт подсвечен и с галочкой.
private struct DropdownMenu<Option: Hashable, Label: View>: View {
    let options: [Option]
    let selection: Option
    @ViewBuilder let label: (Option) -> Label
    let onSelect: (Option) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { offset, option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 12) {
                        label(option)
                        Spacer(minLength: 0)
                        if option == selection {
                            Image("IconCheckGradient")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(option == selection ? Color.white.opacity(0.06) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                if offset < options.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
            }
        }
        .frame(width: 220)
        // В макете — `card` 80% с блюром; поверх строки «Format» значение просвечивает, поэтому сплошной.
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
    }
}

/// Значок пропорции 22pt: прямоугольник 16:9 / 9:16 / 1:1.
private struct AspectIcon: View {
    let aspect: VideoAspect
    let isSelected: Bool

    var body: some View {
        let size: CGSize = switch aspect {
        case .landscape: CGSize(width: 18, height: 10)
        case .portrait: CGSize(width: 10, height: 18)
        case .square: CGSize(width: 18, height: 18)
        }
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.white.opacity(isSelected ? 1 : 0.6), lineWidth: 1.5)
            .frame(width: size.width, height: size.height)
            .frame(width: 22, height: 22)
    }
}

extension VideoAspect {
    var subtitle: LocalizedStringKey {
        switch self {
        case .landscape: "Landscape"
        case .portrait: "Portrait · Stories"
        case .square: "Square"
        }
    }
}

extension TemplatePreviewViewModel.QualityOption {
    /// Название — не перевод, а техническое обозначение.
    var title: String {
        switch self {
        case .p720: "720p"
        case .p1080: "1080p"
        case .p4k: "4K"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .p720: "Faster generation"
        case .p1080: "Recommended"
        case .p4k: "Best quality"
        }
    }
}
