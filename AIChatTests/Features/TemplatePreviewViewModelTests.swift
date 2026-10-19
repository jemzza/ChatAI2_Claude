import Foundation
import Testing
@testable import AIChat

@MainActor
struct TemplatePreviewViewModelTests {
    private struct Created: Equatable {
        let templateId: Int64
        let photo: Data
        let aspect: VideoAspect
        let quality: VideoQuality
    }

    private final class Recorder {
        var created: [Created] = []
        var paywalls = 0
        var opened: [UUID] = []
    }

    private func makeModel(templateId: Int64 = 2, category: String? = nil, isPremium: Bool = true,
                           createError: Error? = nil) -> (TemplatePreviewViewModel, Recorder) {
        let recorder = Recorder()
        let id = UUID()
        let model = TemplatePreviewViewModel(
            templateId: templateId, category: category, api: FakeVideoAPI(),
            subscription: FakeSubscriptionService(isPremium: isPremium)
        ) { template, photo, aspect, quality in
            if let createError { throw createError }
            recorder.created.append(Created(templateId: template.id, photo: photo, aspect: aspect, quality: quality))
            return id
        }
        model.onPaywall = { recorder.paywalls += 1 }
        model.onCreated = { recorder.opened.append($0) }
        return (model, recorder)
    }

    @Test func startsAtTappedTemplateWithinCategory() async {
        let (model, _) = makeModel(templateId: 4, category: "💃 Dance")
        await model.load()
        #expect(model.templates.map(\.id) == [2, 4])
        #expect(model.currentTemplate?.id == 4)
    }

    @Test func createNeedsPhoto() async {
        let (model, recorder) = makeModel()
        await model.load()
        #expect(!model.canCreate)

        await model.loadPhoto { Data([1, 2, 3]) }
        #expect(model.photo == .loaded(Data([1, 2, 3])))
        #expect(model.canCreate)

        model.removePhoto()
        #expect(!model.canCreate)
        await model.create()
        #expect(recorder.created.isEmpty)
    }

    @Test func failedPhotoLoadShowsUploadFailed() async {
        let (model, _) = makeModel()
        await model.loadPhoto { throw URLError(.cannotDecodeContentData) }
        #expect(model.photo == .empty)
        #expect(model.toast?.kind == .failure)
    }

    /// 4K из макета уходит в API как 1080p.
    @Test(arguments: [(TemplatePreviewViewModel.QualityOption.p720, VideoQuality.p720), (.p1080, .p1080), (.p4k, .p1080)])
    func createSendsParameters(option: TemplatePreviewViewModel.QualityOption, expected: VideoQuality) async {
        let (model, recorder) = makeModel()
        await model.load()
        await model.loadPhoto { Data([9]) }
        model.aspect = .portrait
        model.quality = option

        await model.create()

        #expect(recorder.created == [Created(templateId: 2, photo: Data([9]), aspect: .portrait, quality: expected)])
        #expect(recorder.opened.count == 1)
    }

    @Test func freeUserCreateOpensPaywallAndKeepsPhoto() async {
        let (model, recorder) = makeModel(isPremium: false)
        await model.load()
        await model.loadPhoto { Data([9]) }

        await model.create()

        #expect(recorder.paywalls == 1)
        #expect(recorder.created.isEmpty)
        #expect(model.photo == .loaded(Data([9])))
    }

    @Test func invalidPhotoOnCreateResetsSlot() async {
        let (model, _) = makeModel(createError: VideoGenerationService.CreateError.invalidPhoto)
        await model.load()
        await model.loadPhoto { Data([9]) }

        await model.create()

        #expect(model.photo == .empty)
        #expect(model.toast?.kind == .failure)
    }
}
