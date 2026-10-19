import Foundation
import Testing
@testable import AIChat

@MainActor
struct TemplatesViewModelTests {
    private func template(_ id: Int64, _ category: String) -> VideoTemplate {
        VideoTemplate(id: id, name: "T\(id)", category: category, previewURL: nil, qualities: [], duration: 5)
    }

    @Test func categoriesStartWithPopularThenByCount() async {
        let api = FakeVideoAPI(templates: .success([
            template(1, "📈 Trending"), template(2, "💃 Dance"), template(3, "💃 Dance"),
            template(4, "✨ Other"), template(5, "💃 Dance"), template(6, "📈 Trending"), template(7, "🧪 Test"),
        ]))
        let model = TemplatesViewModel(api: api)

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.categories.map(\.title) == ["Popular", "Dance", "Trending", "Other"])
        #expect(model.selectedCategory?.id == nil)
        // «Popular» — все, кроме служебных.
        #expect(model.visibleTemplates.map(\.id) == [1, 2, 3, 4, 5, 6])

        model.selectedCategory = model.categories[1]
        #expect(model.visibleTemplates.map(\.id) == [2, 3, 5])
    }

    @Test func failureShowsErrorAndRetryRecovers() async {
        let api = FakeVideoAPI(templates: .failure(APIError(kind: .offline)))
        let model = TemplatesViewModel(api: api)

        await model.load()
        #expect(model.state == .failed(.offline))

        api.setTemplates(.success([template(1, "📈 Trending")]))
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.visibleTemplates.count == 1)
    }

    @Test func displayTitleDropsEmoji() {
        #expect(TemplatesViewModel.displayTitle("📈 Trending") == "Trending")
        #expect(TemplatesViewModel.displayTitle("❄️ Winter Vibe") == "Winter Vibe")
        #expect(TemplatesViewModel.displayTitle("Plain") == "Plain")
    }
}
