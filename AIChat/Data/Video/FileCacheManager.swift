import Foundation

/// `CacheManaging` на папках в Caches (Videos, Thumbnails, каталог шаблонов).
/// Удалённое скачается заново: экран результата проверяет, есть ли файл.
struct FileCacheManager: CacheManaging {
    let directories: [URL]

    static func standard() -> FileCacheManager {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileCacheManager(directories: [
            caches.appendingPathComponent("Videos", isDirectory: true),
            caches.appendingPathComponent("Thumbnails", isDirectory: true),
        ])
    }

    func size() async -> Int64 {
        let directories = directories
        return await Task.detached(priority: .utility) {
            directories.reduce(Int64(0)) { total, directory in
                let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
                var size: Int64 = 0
                while let url = files?.nextObject() as? URL {
                    size += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                return total + size
            }
        }.value
    }

    func clear() async {
        let directories = directories
        await Task.detached(priority: .utility) {
            for directory in directories { try? FileManager.default.removeItem(at: directory) }
        }.value
    }
}
