import Foundation

public struct TranscriptionResult: Decodable, Sendable {
    public struct APISegment: Decodable, Sendable {
        public let text: String
        public let start: Double
        public let end: Double
        public let speaker: String?

        public init(text: String, start: Double, end: Double, speaker: String?) {
            self.text = text; self.start = start; self.end = end; self.speaker = speaker
        }
    }
    public let text: String
    public let language: String?
    public let segments: [APISegment]?

    public init(text: String, language: String?, segments: [APISegment]?) {
        self.text = text; self.language = language; self.segments = segments
    }
}

public enum APIError: LocalizedError {
    case http(status: Int, body: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Erreur API (HTTP \(status)) : \(body.prefix(300))"
        case .invalidResponse: return "Réponse invalide du serveur"
        }
    }
}

public protocol TranscriptionAPI: Sendable {
    func transcribe(fileURL: URL, apiKey: String) async throws -> TranscriptionResult
}

public struct MistralClient: TranscriptionAPI {
    public init() {}

    static let endpoint = URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!

    static func makeRequest(fileURL: URL, apiKey: String, boundary: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "voxtral-mini-2602")
        field("diarize", "true")
        field("timestamp_granularities", "segment")

        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    public func transcribe(fileURL: URL, apiKey: String) async throws -> TranscriptionResult {
        let request = try Self.makeRequest(fileURL: fileURL, apiKey: apiKey, boundary: "voxtral-\(UUID().uuidString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(TranscriptionResult.self, from: data)
    }
}
