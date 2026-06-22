import Foundation

struct MultipartFormData {
    let boundary = "DailyOPIc-\(UUID().uuidString)"
    private(set) var data = Data()

    mutating func append(name: String, value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append("\(value)\r\n")
    }

    mutating func append(name: String, fileURL: URL, filename: String? = nil) throws {
        let fileData = try Data(contentsOf: fileURL)
        data.append("--\(boundary)\r\n")
        data.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename ?? fileURL.lastPathComponent)\"\r\n"
        )
        data.append("Content-Type: audio/mp4\r\n\r\n")
        data.append(fileData)
        data.append("\r\n")
    }

    mutating func finish() {
        data.append("--\(boundary)--\r\n")
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
