import Foundation

actor TranscriptLogger {
    // MARK: Lifecycle

    init(fileManager: FileManager = .default) {
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("NaviTranscripts", isDirectory: true)
        self.directoryURL = directoryURL

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    // MARK: Internal

    static let shared = TranscriptLogger()

    func transcriptPath(for runID: String) -> String {
        fileURL(for: runID).path
    }

    func log(runID: String, kind: String, payload: some Encodable) async {
        do {
            let payloadData = try JSONEncoder().encode(payload)
            let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
            let lineObject: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "kind": kind,
                "payload": payloadObject,
            ]

            let lineData = try JSONSerialization.data(withJSONObject: lineObject)
            try append(lineData + Data([0x0A]), to: fileURL(for: runID))
        } catch {
            let fallback = "{\"timestamp\":\"\(ISO8601DateFormatter().string(from: Date()))\",\"kind\":\"transcript_error\",\"payload\":{\"message\":\(jsonString(error.localizedDescription))}}\n"
            try? append(Data(fallback.utf8), to: fileURL(for: runID))
        }
    }

    // MARK: Private

    private let directoryURL: URL

    private func fileURL(for runID: String) -> URL {
        directoryURL.appendingPathComponent("\(runID).jsonl")
    }

    private func append(_ data: Data, to fileURL: URL) throws {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func jsonString(_ string: String) -> String {
        let data = try? JSONEncoder().encode(string)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"unknown\""
    }
}
