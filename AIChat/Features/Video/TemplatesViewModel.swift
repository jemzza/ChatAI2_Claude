import Foundation

/// Каталог шаблонов (макет «AI Video — Templates»): категории-чипы и сетка.
/// Первая категория — «Popular» (все шаблоны в порядке каталога), дальше — категории API
/// по числу шаблонов.
@MainActor
final class TemplatesViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case failed(ErrorKind)
    }

    struct Category: Identifiable, Hashable {
        /// Значение `category` из API; `nil` — «Popular» (все).
        let id: String?
        /// Название без эмодзи: «📈 Trending» → «Trending».
        let title: String
    }

    @Published private(set) var state = State.loading
    @Published private(set) var categories: [Category] = []
    @Published var selectedCategory: Category?
    @Published private(set) var templates: [VideoTemplate] = []

    private let api: any VideoAPI
    /// Служебная категория каталога — пользователю не показываем.
    private static let hiddenCategories: Set<String> = ["🧪 Test"]

    init(api: any VideoAPI) {
        self.api = api
    }

    var visibleTemplates: [VideoTemplate] {
        guard let category = selectedCategory?.id else { return templates }
        return templates.filter { $0.category == category }
    }

    func load() async {
        if templates.isEmpty { state = .loading }
        do {
            let all = try await api.templates()
                .filter { !Self.hiddenCategories.contains($0.category) }
            templates = all
            categories = Self.categories(from: all)
            if selectedCategory == nil || !categories.contains(where: { $0 == selectedCategory }) {
                selectedCategory = categories.first
            }
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed((error as? APIError)?.kind ?? .unknown)
        }
    }

    static func categories(from templates: [VideoTemplate]) -> [Category] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for template in templates where !template.category.isEmpty {
            if counts[template.category] == nil { order.append(template.category) }
            counts[template.category, default: 0] += 1
        }
        let sorted = order.enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (counts[lhs.element] ?? 0, counts[rhs.element] ?? 0)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .map(\.element)
        let popular = Category(id: nil, title: String(localized: "Popular"))
        return [popular] + sorted.map { Category(id: $0, title: displayTitle($0)) }
    }

    /// Убирает ведущие эмодзи и пробелы: «✨ Other» → «Other».
    static func displayTitle(_ category: String) -> String {
        let trimmed = category.drop { !$0.isLetter && !$0.isNumber }
        return trimmed.isEmpty ? category : String(trimmed)
    }
}
