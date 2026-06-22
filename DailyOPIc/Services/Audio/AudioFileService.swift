import Foundation

enum AudioFileService {
    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func removeAll(_ answers: [RecordedAnswer]) {
        for answer in answers {
            try? FileManager.default.removeItem(at: answer.audioURL)
        }
    }
}
