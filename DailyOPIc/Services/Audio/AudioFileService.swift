import Foundation

enum AudioFileService {
    static func persistMockAnswer(
        _ source: URL,
        sessionID: String,
        questionNumber: Int
    ) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("MockSessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let destination = directory
            .appendingPathComponent("answer-\(questionNumber)")
            .appendingPathExtension("m4a")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }

    static func removeMockSession(sessionID: String) {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        try? FileManager.default.removeItem(
            at: support
                .appendingPathComponent("MockSessions", isDirectory: true)
                .appendingPathComponent(sessionID, isDirectory: true)
        )
    }
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
