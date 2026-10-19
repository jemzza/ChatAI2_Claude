import Foundation

/// Тело `multipart/form-data`: текстовые поля и файлы.
struct MultipartFormData: Sendable {
    struct File: Sendable {
        let name: String
        let fileName: String
        let mimeType: String
        let data: Data
    }

    private(set) var fields: [(name: String, value: String)] = []
    private(set) var files: [File] = []
    let boundary: String

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func append(_ value: String, name: String) {
        fields.append((name, value))
    }

    mutating func append(_ data: Data, name: String, fileName: String, mimeType: String) {
        files.append(File(name: name, fileName: fileName, mimeType: mimeType, data: data))
    }

    func encoded() -> Data {
        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            body.append("\(field.value)\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
