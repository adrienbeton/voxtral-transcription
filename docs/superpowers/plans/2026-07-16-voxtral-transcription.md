# Voxtral Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS app that transcribes + diarizes audio files via Mistral API, with history, synced audio/transcript playback, speaker renaming, search, and export.

**Architecture:** Swift Package Manager project. `VoxtralCore` library target holds all testable logic (SwiftData models, API client, services, formatters); `Voxtral` executable target holds SwiftUI views; `scripts/bundle.sh` produces `Voxtral.app`. No Xcode project, no third-party dependencies.

**Tech Stack:** Swift 5.10+ / SwiftUI, SwiftData, AVFoundation (AVPlayer), URLSession, Keychain Services.

## Global Constraints

- Platform: macOS 15+, Apple Silicon. App is NOT sandboxed (personal app) — standard bookmarks, no security scope needed.
- API: `POST https://api.mistral.ai/v1/audio/transcriptions`, multipart/form-data, model `voxtral-mini-2602`, `diarize=true`, `timestamp_granularities=["segment"]`. Do NOT send `language` (incompatible with timestamps).
- Audio files are referenced (bookmark), never copied.
- API key lives in macOS Keychain, service name `voxtral-transcription`.
- All code, comments, identifiers in English. UI copy in French.
- Run tests with `swift test`. Build with `swift build`.
- Commit after each task: `git add -A && git commit -m "<type>: <message>"`.

---

### Task 1: SPM scaffolding + app entry

**Files:**
- Create: `Package.swift`, `Sources/VoxtralCore/Placeholder.swift`, `Sources/Voxtral/VoxtralApp.swift`, `Sources/Voxtral/ContentView.swift`, `Tests/VoxtralCoreTests/SmokeTests.swift`, `.gitignore`

**Interfaces:**
- Produces: package layout every later task builds on. Executable target `Voxtral`, library `VoxtralCore`.

- [ ] **Step 1: Write Package.swift and .gitignore**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Voxtral",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "VoxtralCore"),
        .executableTarget(name: "Voxtral", dependencies: ["VoxtralCore"]),
        .testTarget(name: "VoxtralCoreTests", dependencies: ["VoxtralCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.DS_Store
```

- [ ] **Step 2: Minimal sources**

`Sources/VoxtralCore/Placeholder.swift` (deleted in Task 2):
```swift
public enum VoxtralCore { public static let version = "0.1.0" }
```

`Sources/Voxtral/VoxtralApp.swift`:
```swift
import SwiftUI

@main
struct VoxtralApp: App {
    var body: some Scene {
        WindowGroup("Voxtral") {
            ContentView()
        }
    }
}
```

`Sources/Voxtral/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Voxtral")
            .frame(minWidth: 800, minHeight: 500)
    }
}
```

`Tests/VoxtralCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import VoxtralCore

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(VoxtralCore.version, "0.1.0") }
}
```

- [ ] **Step 3: Verify build + tests**

Run: `swift build && swift test`
Expected: build succeeds, 1 test passes.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: SPM scaffolding with VoxtralCore library and Voxtral app targets"
```

---

### Task 2: SwiftData models

**Files:**
- Create: `Sources/VoxtralCore/Models.swift`, `Tests/VoxtralCoreTests/ModelsTests.swift`
- Delete: `Sources/VoxtralCore/Placeholder.swift`, `Tests/VoxtralCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces:
  - `TranscriptionStatus: String, Codable` — `.pending / .done / .failed`
  - `@Model final class Transcription` — see code; `displayName(for speaker: String) -> String`
  - `@Model final class Segment` — `text, start, end, speaker, order, transcription`

- [ ] **Step 1: Write failing test**

`Tests/VoxtralCoreTests/ModelsTests.swift`:
```swift
import XCTest
import SwiftData
@testable import VoxtralCore

final class ModelsTests: XCTestCase {
    @MainActor
    func testCreateAndFetchTranscription() throws {
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let t = Transcription(fileName: "meeting.mp3", fileBookmark: Data(), duration: 120)
        t.segments.append(Segment(text: "Hello", start: 0, end: 2.5, speaker: "speaker_0", order: 0))
        context.insert(t)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Transcription>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].status, .pending)
        XCTAssertEqual(fetched[0].segments.count, 1)
    }

    @MainActor
    func testSpeakerDisplayName() {
        let t = Transcription(fileName: "a.mp3", fileBookmark: Data(), duration: 0)
        XCTAssertEqual(t.displayName(for: "speaker_0"), "Speaker 1")
        t.speakerNames["speaker_0"] = "Adrien"
        XCTAssertEqual(t.displayName(for: "speaker_0"), "Adrien")
        XCTAssertEqual(t.displayName(for: "weird_id"), "weird_id")
    }
}
```

- [ ] **Step 2: Run test, verify it fails** (`swift test` — compile error: types not defined)

- [ ] **Step 3: Implement models**

`Sources/VoxtralCore/Models.swift`:
```swift
import Foundation
import SwiftData

public enum TranscriptionStatus: String, Codable, Sendable {
    case pending, done, failed
}

@Model
public final class Transcription {
    public var id: UUID = UUID()
    public var fileName: String = ""
    public var fileBookmark: Data = Data()
    public var createdAt: Date = Date()
    public var duration: TimeInterval = 0
    public var detectedLanguage: String?
    public var statusRaw: String = TranscriptionStatus.pending.rawValue
    public var errorMessage: String?
    public var fullText: String = ""
    public var speakerNames: [String: String] = [:]
    @Relationship(deleteRule: .cascade, inverse: \Segment.transcription)
    public var segments: [Segment] = []

    public var status: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    public var orderedSegments: [Segment] {
        segments.sorted { $0.order < $1.order }
    }

    /// Custom name if set, else "Speaker N" derived from "speaker_<n>" ids, else the raw id.
    public func displayName(for speaker: String) -> String {
        if let custom = speakerNames[speaker], !custom.isEmpty { return custom }
        if speaker.hasPrefix("speaker_"), let n = Int(speaker.dropFirst("speaker_".count)) {
            return "Speaker \(n + 1)"
        }
        return speaker
    }

    public init(fileName: String, fileBookmark: Data, duration: TimeInterval) {
        self.fileName = fileName
        self.fileBookmark = fileBookmark
        self.duration = duration
    }
}

@Model
public final class Segment {
    public var text: String = ""
    public var start: TimeInterval = 0
    public var end: TimeInterval = 0
    public var speaker: String = ""
    public var order: Int = 0
    public var transcription: Transcription?

    public init(text: String, start: TimeInterval, end: TimeInterval, speaker: String, order: Int) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
        self.order = order
    }
}
```

- [ ] **Step 4: Run tests, verify pass** (`swift test`)

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: SwiftData models Transcription and Segment"`

---

### Task 3: Mistral API client

**Files:**
- Create: `Sources/VoxtralCore/MistralClient.swift`, `Tests/VoxtralCoreTests/MistralClientTests.swift`

**Interfaces:**
- Produces:
  - `struct TranscriptionResult: Decodable` with `text: String`, `language: String?`, `segments: [APISegment]?`; `APISegment` has `text: String, start: Double, end: Double, speaker: String?`
  - `protocol TranscriptionAPI: Sendable { func transcribe(fileURL: URL, apiKey: String) async throws -> TranscriptionResult }`
  - `struct MistralClient: TranscriptionAPI`
  - `enum APIError: LocalizedError` — `.http(status: Int, body: String)`, `.invalidResponse`

- [ ] **Step 1: Write failing tests**

`Tests/VoxtralCoreTests/MistralClientTests.swift`:
```swift
import XCTest
@testable import VoxtralCore

final class MistralClientTests: XCTestCase {
    func testDecodeResponseWithDiarization() throws {
        let json = """
        {"model":"voxtral-mini-2602","text":"Hello there. Hi.","language":"en",
         "segments":[
           {"text":"Hello there.","start":0.0,"end":1.8,"speaker":"speaker_0"},
           {"text":"Hi.","start":2.0,"end":2.6,"speaker":"speaker_1"}
         ]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(TranscriptionResult.self, from: json)
        XCTAssertEqual(r.text, "Hello there. Hi.")
        XCTAssertEqual(r.language, "en")
        XCTAssertEqual(r.segments?.count, 2)
        XCTAssertEqual(r.segments?[1].speaker, "speaker_1")
    }

    func testDecodeResponseWithoutSegments() throws {
        let json = #"{"text":"Hello.","language":null}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(TranscriptionResult.self, from: json)
        XCTAssertEqual(r.text, "Hello.")
        XCTAssertNil(r.segments)
    }

    func testMultipartBody() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).mp3")
        try Data([0x49, 0x44, 0x33]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let request = try MistralClient.makeRequest(fileURL: tmp, apiKey: "sk-test", boundary: "BOUNDARY")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=BOUNDARY")

        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nvoxtral-mini-2602"))
        XCTAssertTrue(body.contains("name=\"diarize\"\r\n\r\ntrue"))
        XCTAssertTrue(body.contains("name=\"timestamp_granularities\"\r\n\r\nsegment"))
        XCTAssertTrue(body.contains("filename=\"\(tmp.lastPathComponent)\""))
        XCTAssertTrue(body.hasSuffix("--BOUNDARY--\r\n"))
        XCTAssertFalse(body.contains("name=\"language\""))
    }
}
```

- [ ] **Step 2: Run tests, verify failure** (compile error)

- [ ] **Step 3: Implement client**

`Sources/VoxtralCore/MistralClient.swift`:
```swift
import Foundation

public struct TranscriptionResult: Decodable, Sendable {
    public struct APISegment: Decodable, Sendable {
        public let text: String
        public let start: Double
        public let end: Double
        public let speaker: String?
    }
    public let text: String
    public let language: String?
    public let segments: [APISegment]?
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
```

- [ ] **Step 4: Run tests, verify pass** (`swift test`)

- [ ] **Step 5: Commit** — `git commit -am "feat: Mistral transcription API client with multipart upload"`

---

### Task 4: Keychain store

**Files:**
- Create: `Sources/VoxtralCore/KeychainStore.swift`, `Tests/VoxtralCoreTests/KeychainStoreTests.swift`

**Interfaces:**
- Produces: `enum KeychainStore { static func apiKey() -> String?; static func setAPIKey(_ key: String) throws; static func deleteAPIKey() }` — uses generic password, service `voxtral-transcription`, account `mistral-api-key`. Tests use a distinct service via internal `service` parameter overload.

- [ ] **Step 1: Write failing test**

`Tests/VoxtralCoreTests/KeychainStoreTests.swift`:
```swift
import XCTest
@testable import VoxtralCore

final class KeychainStoreTests: XCTestCase {
    let service = "voxtral-transcription-tests"

    override func tearDown() { KeychainStore.deleteAPIKey(service: service) }

    func testRoundTrip() throws {
        XCTAssertNil(KeychainStore.apiKey(service: service))
        try KeychainStore.setAPIKey("sk-abc", service: service)
        XCTAssertEqual(KeychainStore.apiKey(service: service), "sk-abc")
        try KeychainStore.setAPIKey("sk-updated", service: service)
        XCTAssertEqual(KeychainStore.apiKey(service: service), "sk-updated")
        KeychainStore.deleteAPIKey(service: service)
        XCTAssertNil(KeychainStore.apiKey(service: service))
    }
}
```

- [ ] **Step 2: Run test, verify failure**

- [ ] **Step 3: Implement**

`Sources/VoxtralCore/KeychainStore.swift`:
```swift
import Foundation
import Security

public enum KeychainStore {
    static let defaultService = "voxtral-transcription"
    static let account = "mistral-api-key"

    static func baseQuery(service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func apiKey(service: String = defaultService) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func setAPIKey(_ key: String, service: String = defaultService) throws {
        deleteAPIKey(service: service)
        var query = baseQuery(service: service)
        query[kSecValueData as String] = Data(key.utf8)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    public static func deleteAPIKey(service: String = defaultService) {
        SecItemDelete(baseQuery(service: service) as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Commit** — `git commit -am "feat: Keychain storage for Mistral API key"`

---

### Task 5: TranscriptionService + bookmarks

**Files:**
- Create: `Sources/VoxtralCore/TranscriptionService.swift`, `Tests/VoxtralCoreTests/TranscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `TranscriptionAPI`, `Transcription`, `Segment` (Tasks 2–3)
- Produces:
  - `extension Transcription { func resolvedFileURL() -> URL? }` (resolves bookmark, nil if stale/missing file)
  - `@MainActor final class TranscriptionService { init(api: TranscriptionAPI, context: ModelContext); func importFile(_ url: URL) async -> Transcription; func retry(_ t: Transcription) async }`
  - `enum ServiceError: LocalizedError { case missingAPIKey, missingFile }`
  - Service reads key via `KeychainStore.apiKey()`; sets status/errorMessage on failure; fills segments, fullText, detectedLanguage on success. Audio duration read with `AVURLAsset.load(.duration)`.

- [ ] **Step 1: Write failing tests**

`Tests/VoxtralCoreTests/TranscriptionServiceTests.swift`:
```swift
import XCTest
import SwiftData
@testable import VoxtralCore

struct MockAPI: TranscriptionAPI {
    var result: Result<TranscriptionResult, Error>
    func transcribe(fileURL: URL, apiKey: String) async throws -> TranscriptionResult {
        try result.get()
    }
}

final class TranscriptionServiceTests: XCTestCase {
    @MainActor
    func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Transcription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return container.mainContext
    }

    func makeAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc-\(UUID()).mp3")
        try Data([0x49, 0x44, 0x33, 0x00]).write(to: url)
        return url
    }

    @MainActor
    func testImportSuccess() async throws {
        let context = try makeContext()
        let json = TranscriptionResult(
            text: "Bonjour. Salut.", language: "fr",
            segments: [
                .init(text: "Bonjour.", start: 0, end: 1, speaker: "speaker_0"),
                .init(text: "Salut.", start: 1.2, end: 2, speaker: "speaker_1"),
            ])
        let service = TranscriptionService(api: MockAPI(result: .success(json)), context: context,
                                           apiKeyProvider: { "sk-test" })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .done)
        XCTAssertEqual(t.fullText, "Bonjour. Salut.")
        XCTAssertEqual(t.detectedLanguage, "fr")
        XCTAssertEqual(t.orderedSegments.count, 2)
        XCTAssertEqual(t.orderedSegments[1].speaker, "speaker_1")
        XCTAssertNotNil(t.resolvedFileURL())
    }

    @MainActor
    func testImportAPIFailure() async throws {
        let context = try makeContext()
        let service = TranscriptionService(
            api: MockAPI(result: .failure(APIError.http(status: 401, body: "unauthorized"))),
            context: context, apiKeyProvider: { "sk-bad" })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .failed)
        XCTAssertNotNil(t.errorMessage)
    }

    @MainActor
    func testImportWithoutAPIKey() async throws {
        let context = try makeContext()
        let service = TranscriptionService(api: MockAPI(result: .failure(APIError.invalidResponse)),
                                           context: context, apiKeyProvider: { nil })
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = await service.importFile(url)
        XCTAssertEqual(t.status, .failed)
        XCTAssertEqual(t.errorMessage, ServiceError.missingAPIKey.errorDescription)
    }

    @MainActor
    func testRetryAfterFailure() async throws {
        let context = try makeContext()
        let url = try makeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let failing = TranscriptionService(
            api: MockAPI(result: .failure(APIError.invalidResponse)),
            context: context, apiKeyProvider: { "sk" })
        let t = await failing.importFile(url)
        XCTAssertEqual(t.status, .failed)

        let ok = TranscriptionResult(text: "Hello", language: "en",
                                     segments: [.init(text: "Hello", start: 0, end: 1, speaker: "speaker_0")])
        let succeeding = TranscriptionService(api: MockAPI(result: .success(ok)),
                                              context: context, apiKeyProvider: { "sk" })
        await succeeding.retry(t)
        XCTAssertEqual(t.status, .done)
        XCTAssertNil(t.errorMessage)
        XCTAssertEqual(t.orderedSegments.count, 1)
    }
}
```

Note: `TranscriptionResult` needs a memberwise init usable from tests — add `public init(text:language:segments:)` and `public init(text:start:end:speaker:)` on `APISegment` in `MistralClient.swift`.

- [ ] **Step 2: Run tests, verify failure**

- [ ] **Step 3: Implement service**

Add public inits to `TranscriptionResult` / `APISegment` in `MistralClient.swift`:
```swift
// inside APISegment
public init(text: String, start: Double, end: Double, speaker: String?) {
    self.text = text; self.start = start; self.end = end; self.speaker = speaker
}
// inside TranscriptionResult
public init(text: String, language: String?, segments: [APISegment]?) {
    self.text = text; self.language = language; self.segments = segments
}
```

`Sources/VoxtralCore/TranscriptionService.swift`:
```swift
import Foundation
import SwiftData
import AVFoundation

public enum ServiceError: LocalizedError {
    case missingAPIKey
    case missingFile

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Clé API Mistral manquante — ajoute-la dans les Réglages."
        case .missingFile: return "Fichier audio introuvable."
        }
    }
}

extension Transcription {
    /// Resolves the stored bookmark; returns nil if the file is gone.
    public func resolvedFileURL() -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: fileBookmark, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale, let fresh = try? url.bookmarkData() { fileBookmark = fresh }
        return url
    }
}

@MainActor
public final class TranscriptionService {
    let api: TranscriptionAPI
    let context: ModelContext
    let apiKeyProvider: () -> String?

    public init(api: TranscriptionAPI = MistralClient(),
                context: ModelContext,
                apiKeyProvider: @escaping () -> String? = { KeychainStore.apiKey() }) {
        self.api = api
        self.context = context
        self.apiKeyProvider = apiKeyProvider
    }

    @discardableResult
    public func importFile(_ url: URL) async -> Transcription {
        let bookmark = (try? url.bookmarkData()) ?? Data()
        let duration = await loadDuration(url)
        let t = Transcription(fileName: url.lastPathComponent, fileBookmark: bookmark, duration: duration)
        context.insert(t)
        try? context.save()
        await run(t, fileURL: url)
        return t
    }

    public func retry(_ t: Transcription) async {
        guard let url = t.resolvedFileURL() else {
            t.status = .failed
            t.errorMessage = ServiceError.missingFile.errorDescription
            try? context.save()
            return
        }
        await run(t, fileURL: url)
    }

    func run(_ t: Transcription, fileURL: URL) async {
        t.status = .pending
        t.errorMessage = nil
        try? context.save()

        guard let key = apiKeyProvider(), !key.isEmpty else {
            t.status = .failed
            t.errorMessage = ServiceError.missingAPIKey.errorDescription
            try? context.save()
            return
        }
        do {
            let result = try await api.transcribe(fileURL: fileURL, apiKey: key)
            for old in t.segments { context.delete(old) }
            t.segments = []
            for (i, s) in (result.segments ?? []).enumerated() {
                t.segments.append(Segment(text: s.text, start: s.start, end: s.end,
                                          speaker: s.speaker ?? "speaker_0", order: i))
            }
            t.fullText = result.text
            t.detectedLanguage = result.language
            t.status = .done
        } catch {
            t.status = .failed
            t.errorMessage = error.localizedDescription
        }
        try? context.save()
    }

    func loadDuration(_ url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }
}
```

- [ ] **Step 4: Run tests, verify pass** (`swift test`)

- [ ] **Step 5: Commit** — `git commit -am "feat: transcription service with bookmark resolution and retry"`

---

### Task 6: Export formatter

**Files:**
- Create: `Sources/VoxtralCore/ExportFormatter.swift`, `Tests/VoxtralCoreTests/ExportFormatterTests.swift`

**Interfaces:**
- Consumes: `Transcription.orderedSegments`, `displayName(for:)`
- Produces:
  - `enum ExportFormatter { static func plainText(_ t: Transcription) -> String; static func markdown(_ t: Transcription) -> String; static func timestamp(_ seconds: TimeInterval) -> String }`
  - plainText: one line per segment `[Name] text`. markdown: `**Name** [hh:mm:ss] : text` per line, preceded by `# fileName` header and blank line.

- [ ] **Step 1: Write failing test**

`Tests/VoxtralCoreTests/ExportFormatterTests.swift`:
```swift
import XCTest
@testable import VoxtralCore

final class ExportFormatterTests: XCTestCase {
    @MainActor
    func makeTranscription() -> Transcription {
        let t = Transcription(fileName: "meeting.mp3", fileBookmark: Data(), duration: 4000)
        t.speakerNames["speaker_0"] = "Adrien"
        t.segments = [
            Segment(text: "Bonjour à tous.", start: 0, end: 2, speaker: "speaker_0", order: 0),
            Segment(text: "Salut.", start: 3661.5, end: 3663, speaker: "speaker_1", order: 1),
        ]
        return t
    }

    func testTimestamp() {
        XCTAssertEqual(ExportFormatter.timestamp(0), "00:00:00")
        XCTAssertEqual(ExportFormatter.timestamp(3661.5), "01:01:01")
    }

    @MainActor
    func testPlainText() {
        let out = ExportFormatter.plainText(makeTranscription())
        XCTAssertEqual(out, "[Adrien] Bonjour à tous.\n[Speaker 2] Salut.")
    }

    @MainActor
    func testMarkdown() {
        let out = ExportFormatter.markdown(makeTranscription())
        XCTAssertEqual(out, """
        # meeting.mp3

        **Adrien** [00:00:00] : Bonjour à tous.
        **Speaker 2** [01:01:01] : Salut.
        """)
    }
}
```

- [ ] **Step 2: Run test, verify failure**

- [ ] **Step 3: Implement**

`Sources/VoxtralCore/ExportFormatter.swift`:
```swift
import Foundation

public enum ExportFormatter {
    public static func timestamp(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    @MainActor
    public static func plainText(_ t: Transcription) -> String {
        t.orderedSegments
            .map { "[\(t.displayName(for: $0.speaker))] \($0.text)" }
            .joined(separator: "\n")
    }

    @MainActor
    public static func markdown(_ t: Transcription) -> String {
        let lines = t.orderedSegments
            .map { "**\(t.displayName(for: $0.speaker))** [\(timestamp($0.start))] : \($0.text)" }
            .joined(separator: "\n")
        return "# \(t.fileName)\n\n\(lines)"
    }
}
```

Note: `@MainActor` because `@Model` classes are main-actor bound in this setup; if the compiler does not require it, drop the annotation.

- [ ] **Step 4: Run tests, verify pass**

- [ ] **Step 5: Commit** — `git commit -am "feat: transcript export formatter (txt, markdown)"`

---

### Task 7: UI shell — sidebar, import, settings

**Files:**
- Modify: `Sources/Voxtral/VoxtralApp.swift`, `Sources/Voxtral/ContentView.swift`
- Create: `Sources/Voxtral/SidebarView.swift`, `Sources/Voxtral/SettingsView.swift`, `Sources/Voxtral/AppState.swift`

**Interfaces:**
- Consumes: `Transcription`, `TranscriptionService`, `KeychainStore` (VoxtralCore)
- Produces:
  - `@MainActor @Observable final class AppState` — `var selection: Transcription?`, `func importFiles(_ urls: [URL], context: ModelContext)`
  - `SidebarView(selection: Binding<Transcription?>, searchText: String)` — filtered `@Query` list
  - `TranscriptionDetailView(transcription: Transcription)` placeholder (replaced Task 8)
  - UI copy in French.

- [ ] **Step 1: Implement app entry + state**

`Sources/Voxtral/VoxtralApp.swift`:
```swift
import SwiftUI
import SwiftData
import VoxtralCore

@main
struct VoxtralApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Voxtral") {
            ContentView()
                .environment(appState)
        }
        .modelContainer(for: Transcription.self)

        Settings {
            SettingsView()
        }
    }
}
```

`Sources/Voxtral/AppState.swift`:
```swift
import SwiftUI
import SwiftData
import VoxtralCore

@MainActor
@Observable
final class AppState {
    var selection: Transcription?

    func importFiles(_ urls: [URL], context: ModelContext) {
        let service = TranscriptionService(context: context)
        for url in urls {
            Task {
                let t = await service.importFile(url)
                if selection == nil { selection = t }
            }
        }
    }
}
```

- [ ] **Step 2: Implement ContentView with split view, drop and file importer**

`Sources/Voxtral/ContentView.swift`:
```swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import VoxtralCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var showImporter = false

    static let audioTypes: [UTType] = [.mp3, .wav, .aiff, .mpeg4Audio, UTType("org.xiph.flac") ?? .audio, .audio]

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            SidebarView(selection: $appState.selection, searchText: searchText)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Rechercher")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let t = appState.selection {
                TranscriptionDetailView(transcription: t)
            } else {
                ContentUnavailableView("Aucune transcription",
                                       systemImage: "waveform",
                                       description: Text("Glisse un fichier audio ici ou clique sur Ouvrir."))
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ouvrir", systemImage: "plus") { showImporter = true }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.audioTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                appState.importFiles(urls, context: context)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let audio = urls.filter { url in
                UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
            }
            guard !audio.isEmpty else { return false }
            appState.importFiles(audio, context: context)
            return true
        }
    }
}
```

- [ ] **Step 3: Implement SidebarView with filtering + delete**

`Sources/Voxtral/SidebarView.swift`:
```swift
import SwiftUI
import SwiftData
import VoxtralCore

struct SidebarView: View {
    @Binding var selection: Transcription?
    let searchText: String
    @Environment(\.modelContext) private var context
    @Query(sort: \Transcription.createdAt, order: .reverse) private var transcriptions: [Transcription]

    var filtered: [Transcription] {
        guard !searchText.isEmpty else { return transcriptions }
        let q = searchText.localizedLowercase
        return transcriptions.filter {
            $0.fileName.localizedLowercase.contains(q) || $0.fullText.localizedLowercase.contains(q)
        }
    }

    var body: some View {
        List(filtered, id: \.persistentModelID, selection: $selection) { t in
            NavigationLink(value: t) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        statusIcon(t.status)
                        Text(t.fileName).fontWeight(.medium).lineLimit(1)
                    }
                    Text("\(t.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(ExportFormatter.timestamp(t.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tag(t)
            .contextMenu {
                Button("Supprimer", role: .destructive) {
                    if selection == t { selection = nil }
                    context.delete(t)
                    try? context.save()
                }
            }
        }
    }

    @ViewBuilder
    func statusIcon(_ status: TranscriptionStatus) -> some View {
        switch status {
        case .pending: ProgressView().controlSize(.small)
        case .done: EmptyView()
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }
}
```

Placeholder detail (replaced in Task 8) — append to `SidebarView.swift` bottom or its own file:
```swift
struct TranscriptionDetailView: View {
    let transcription: Transcription
    var body: some View { Text(transcription.fileName) }
}
```

- [ ] **Step 4: Implement SettingsView**

`Sources/Voxtral/SettingsView.swift`:
```swift
import SwiftUI
import VoxtralCore

struct SettingsView: View {
    @State private var apiKey: String = KeychainStore.apiKey() ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            SecureField("Clé API Mistral", text: $apiKey)
                .onChange(of: apiKey) { saved = false }
            HStack {
                Button("Enregistrer") {
                    try? KeychainStore.setAPIKey(apiKey)
                    saved = true
                }
                if saved {
                    Label("Enregistrée dans le trousseau", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            Link("Obtenir une clé sur console.mistral.ai",
                 destination: URL(string: "https://console.mistral.ai")!)
        }
        .padding(20)
        .frame(width: 420)
    }
}
```

- [ ] **Step 5: Verify build + smoke run**

Run: `swift build && swift test`
Expected: builds, all tests still pass.
Run: `swift run Voxtral &` briefly — window opens with empty state; then kill it.

- [ ] **Step 6: Commit** — `git commit -am "feat: UI shell with sidebar history, import, settings"`

---

### Task 8: Player + synced transcript

**Files:**
- Create: `Sources/Voxtral/PlayerController.swift`, `Sources/Voxtral/TranscriptionDetailView.swift`, `Sources/Voxtral/PlayerBarView.swift`, `Sources/VoxtralCore/SegmentLocator.swift`
- Modify: `Sources/Voxtral/SidebarView.swift` (remove placeholder `TranscriptionDetailView`)
- Create: `Tests/VoxtralCoreTests/SegmentLocatorTests.swift`

**Interfaces:**
- Consumes: `Transcription.orderedSegments`, `resolvedFileURL()`
- Produces:
  - `public enum SegmentLocator { public static func index(at time: TimeInterval, in segments: [(start: TimeInterval, end: TimeInterval)]) -> Int? }` — current segment index for playback time (last segment whose start <= time, nil before first)
  - `@MainActor @Observable final class PlayerController` — `var currentTime: TimeInterval`, `var isPlaying: Bool`, `var rate: Float`, `var duration: TimeInterval`, `func load(url: URL)`, `func togglePlay()`, `func seek(to: TimeInterval)`
  - `TranscriptionDetailView(transcription: Transcription)` — full detail UI

- [ ] **Step 1: Write failing test for SegmentLocator**

`Tests/VoxtralCoreTests/SegmentLocatorTests.swift`:
```swift
import XCTest
@testable import VoxtralCore

final class SegmentLocatorTests: XCTestCase {
    let segments: [(start: TimeInterval, end: TimeInterval)] = [(0, 2), (2.5, 5), (6, 9)]

    func testLocate() {
        XCTAssertEqual(SegmentLocator.index(at: 0, in: segments), 0)
        XCTAssertEqual(SegmentLocator.index(at: 1.9, in: segments), 0)
        XCTAssertEqual(SegmentLocator.index(at: 2.2, in: segments), 0) // gap: stick to previous
        XCTAssertEqual(SegmentLocator.index(at: 3, in: segments), 1)
        XCTAssertEqual(SegmentLocator.index(at: 100, in: segments), 2)
        XCTAssertNil(SegmentLocator.index(at: -1, in: segments))
        XCTAssertNil(SegmentLocator.index(at: 0, in: []))
    }
}
```

- [ ] **Step 2: Run test, verify failure, then implement**

`Sources/VoxtralCore/SegmentLocator.swift`:
```swift
import Foundation

public enum SegmentLocator {
    /// Index of the segment active at `time`: the last segment whose start <= time.
    public static func index(at time: TimeInterval,
                             in segments: [(start: TimeInterval, end: TimeInterval)]) -> Int? {
        guard time >= 0 else { return nil }
        var result: Int?
        for (i, s) in segments.enumerated() where s.start <= time { result = i }
        return result
    }
}
```

Run: `swift test` — passes.

- [ ] **Step 3: Implement PlayerController**

`Sources/Voxtral/PlayerController.swift`:
```swift
import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class PlayerController {
    private var player: AVPlayer?
    private var timeObserver: Any?

    var currentTime: TimeInterval = 0
    var isPlaying = false
    var duration: TimeInterval = 0
    var rate: Float = 1.0 {
        didSet { if isPlaying { player?.rate = rate } }
    }

    func load(url: URL) {
        unload()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p
        Task {
            if let d = try? await item.asset.load(.duration) {
                duration = CMTimeGetSeconds(d).isFinite ? CMTimeGetSeconds(d) : 0
            }
        }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if let p = self.player, p.timeControlStatus != .playing, self.isPlaying,
                   p.currentItem?.isPlaybackLikelyToKeepUp == false {
                    // buffering; keep state
                }
                if let item = p.currentItem, item.duration.isNumeric,
                   CMTimeGetSeconds(item.duration) - self.currentTime < 0.05 {
                    self.isPlaying = false
                }
            }
        }
    }

    func unload() {
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        player?.pause()
        player = nil
        currentTime = 0
        isPlaying = false
        duration = 0
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0, duration - currentTime < 0.1 { seek(to: 0) }
            player.rate = rate
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
```

- [ ] **Step 4: Implement detail view + player bar**

Remove the placeholder `TranscriptionDetailView` from `SidebarView.swift`.

`Sources/Voxtral/PlayerBarView.swift`:
```swift
import SwiftUI
import VoxtralCore

struct PlayerBarView: View {
    @Bindable var player: PlayerController

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Text(ExportFormatter.timestamp(player.currentTime))
                .font(.caption.monospacedDigit())

            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(player.duration, 1))

            Text(ExportFormatter.timestamp(player.duration))
                .font(.caption.monospacedDigit())

            Picker("", selection: $player.rate) {
                Text("1×").tag(Float(1.0))
                Text("1,5×").tag(Float(1.5))
                Text("2×").tag(Float(2.0))
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
```

`Sources/Voxtral/TranscriptionDetailView.swift`:
```swift
import SwiftUI
import SwiftData
import VoxtralCore

struct TranscriptionDetailView: View {
    let transcription: Transcription
    @State private var player = PlayerController()
    @State private var audioAvailable = true

    static let speakerColors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]

    var speakers: [String] {
        Array(Set(transcription.orderedSegments.map(\.speaker))).sorted()
    }

    func color(for speaker: String) -> Color {
        let i = speakers.firstIndex(of: speaker) ?? 0
        return Self.speakerColors[i % Self.speakerColors.count]
    }

    var currentSegmentIndex: Int? {
        let ranges = transcription.orderedSegments.map { (start: $0.start, end: $0.end) }
        return SegmentLocator.index(at: player.currentTime, in: ranges)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch transcription.status {
            case .pending:
                Spacer()
                ProgressView("Transcription en cours…")
                Spacer()
            case .failed:
                FailedView(transcription: transcription)
            case .done:
                transcriptBody
            }
        }
        .navigationTitle(transcription.fileName)
        .onAppear { loadAudio() }
        .onChange(of: transcription.persistentModelID) { loadAudio() }
        .onDisappear { player.unload() }
    }

    var transcriptBody: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(transcription.orderedSegments.enumerated()), id: \.offset) { i, segment in
                            SegmentRow(
                                segment: segment,
                                name: transcription.displayName(for: segment.speaker),
                                color: color(for: segment.speaker),
                                isCurrent: i == currentSegmentIndex
                            )
                            .id(i)
                            .onTapGesture {
                                if audioAvailable { player.seek(to: segment.start) }
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: currentSegmentIndex) { _, newIndex in
                    if let newIndex, player.isPlaying {
                        withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                }
            }
            Divider()
            if audioAvailable {
                PlayerBarView(player: player)
            } else {
                Label("Fichier audio introuvable — lecture désactivée", systemImage: "speaker.slash")
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }

    func loadAudio() {
        player.unload()
        if let url = transcription.resolvedFileURL() {
            audioAvailable = true
            player.load(url: url)
        } else {
            audioAvailable = false
        }
    }
}

struct SegmentRow: View {
    let segment: Segment
    let name: String
    let color: Color
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.caption.bold()).foregroundStyle(color)
                    Text(ExportFormatter.timestamp(segment.start))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(segment.text)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(isCurrent ? Color.accentColor.opacity(0.15) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

struct FailedView: View {
    let transcription: Transcription
    @Environment(\.modelContext) private var context

    var body: some View {
        Spacer()
        ContentUnavailableView {
            Label("Échec de la transcription", systemImage: "exclamationmark.triangle")
        } description: {
            Text(transcription.errorMessage ?? "Erreur inconnue")
        } actions: {
            Button("Réessayer") {
                let service = TranscriptionService(context: context)
                Task { await service.retry(transcription) }
            }
            SettingsLink { Text("Réglages…") }
        }
        Spacer()
    }
}
```

- [ ] **Step 5: Verify build + tests, smoke run**

Run: `swift build && swift test` — all pass.

- [ ] **Step 6: Commit** — `git commit -am "feat: audio player with bidirectional transcript sync"`

---

### Task 9: Speaker renaming, in-transcript search, copy/export

**Files:**
- Modify: `Sources/Voxtral/TranscriptionDetailView.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: final detail-view feature set. Speaker rename popover writes to `transcription.speakerNames` and saves context. Find bar (⌘F) with next/prev. Toolbar Copier + Exporter.

- [ ] **Step 1: Add speaker rename popover**

In `SegmentRow`, make the name a button. Add to `SegmentRow`:
```swift
// new properties
let onRename: (String) -> Void
@State private var showRename = false
@State private var draft = ""
```
Replace `Text(name)...` with:
```swift
Button(name) { draft = name; showRename = true }
    .buttonStyle(.plain)
    .font(.caption.bold())
    .foregroundStyle(color)
    .popover(isPresented: $showRename) {
        Form {
            TextField("Nom du speaker", text: $draft)
                .frame(width: 200)
                .onSubmit { onRename(draft); showRename = false }
            Button("Renommer") { onRename(draft); showRename = false }
        }
        .padding(12)
    }
```
In `TranscriptionDetailView`, pass the callback:
```swift
onRename: { newName in
    transcription.speakerNames[segment.speaker] = newName
    try? context.save()
}
```
(add `@Environment(\.modelContext) private var context` to `TranscriptionDetailView`).

- [ ] **Step 2: Add find bar with ⌘F, highlight, next/prev**

Add state to `TranscriptionDetailView`:
```swift
@State private var findQuery = ""
@State private var showFind = false
@State private var findCursor = 0
@FocusState private var findFocused: Bool

var matchIndices: [Int] {
    guard !findQuery.isEmpty else { return [] }
    let q = findQuery.localizedLowercase
    return transcription.orderedSegments.enumerated()
        .filter { $0.element.text.localizedLowercase.contains(q) }
        .map(\.offset)
}
```
Insert the find bar at the top of `transcriptBody`'s `VStack` (above the ScrollViewReader):
```swift
if showFind {
    HStack {
        Image(systemName: "magnifyingglass")
        TextField("Rechercher dans le transcript", text: $findQuery)
            .textFieldStyle(.plain)
            .focused($findFocused)
            .onSubmit { advanceFind(1) }
        if !matchIndices.isEmpty {
            Text("\(findCursor + 1)/\(matchIndices.count)").font(.caption).foregroundStyle(.secondary)
        }
        Button(action: { advanceFind(-1) }) { Image(systemName: "chevron.up") }
            .disabled(matchIndices.isEmpty)
        Button(action: { advanceFind(1) }) { Image(systemName: "chevron.down") }
            .disabled(matchIndices.isEmpty)
        Button(action: { showFind = false; findQuery = "" }) { Image(systemName: "xmark.circle.fill") }
            .buttonStyle(.plain)
    }
    .padding(8)
    .background(.bar)
    Divider()
}
```
`advanceFind` needs the ScrollViewReader proxy; store it via a small trick — move `scrollProxy` capture:
```swift
@State private var scrollTarget: Int?

func advanceFind(_ delta: Int) {
    guard !matchIndices.isEmpty else { return }
    findCursor = ((findCursor + delta) % matchIndices.count + matchIndices.count) % matchIndices.count
    let idx = matchIndices[findCursor]
    scrollTarget = idx
    if audioAvailable { player.seek(to: transcription.orderedSegments[idx].start) }
}
```
Inside the `ScrollViewReader` closure add:
```swift
.onChange(of: scrollTarget) { _, target in
    if let target { withAnimation { proxy.scrollTo(target, anchor: .center) };
        scrollTarget = nil }
}
.onChange(of: findQuery) { findCursor = 0 }
```
Pass highlight info to `SegmentRow` (new properties `highlight: String`, `isFindMatch: Bool`):
```swift
isFindMatch: matchIndices.contains(i),
highlight: findQuery
```
In `SegmentRow`, render text with highlight:
```swift
var highlightedText: AttributedString {
    var attr = AttributedString(segment.text)
    guard !highlight.isEmpty else { return attr }
    var searchStart = attr.startIndex
    let lowerText = segment.text.lowercased()
    let lowerQuery = highlight.lowercased()
    var searchRange = lowerText.startIndex..<lowerText.endIndex
    while let r = lowerText.range(of: lowerQuery, range: searchRange) {
        let lower = lowerText.distance(from: lowerText.startIndex, to: r.lowerBound)
        let length = lowerText.distance(from: r.lowerBound, to: r.upperBound)
        if let attrStart = attr.index(attr.startIndex, offsetByCharacters: lower) as AttributedString.Index?,
           let attrEnd = attr.index(attrStart, offsetByCharacters: length) as AttributedString.Index? {
            attr[attrStart..<attrEnd].backgroundColor = .yellow.opacity(0.5)
        }
        searchRange = r.upperBound..<lowerText.endIndex
        _ = searchStart
    }
    return attr
}
```
Use `Text(highlightedText)` instead of `Text(segment.text)`. Add border for `isFindMatch`:
```swift
.overlay(RoundedRectangle(cornerRadius: 6)
    .stroke(isFindMatch ? Color.yellow.opacity(0.8) : .clear, lineWidth: 1))
```
Wire ⌘F: on `transcriptBody`'s outer VStack add:
```swift
.background {
    Button("") { showFind = true; findFocused = true }
        .keyboardShortcut("f", modifiers: .command)
        .hidden()
}
```

- [ ] **Step 3: Add Copier / Exporter toolbar buttons**

On `TranscriptionDetailView` body add:
```swift
.toolbar {
    ToolbarItemGroup(placement: .automatic) {
        Button("Copier", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ExportFormatter.plainText(transcription), forType: .string)
        }
        .disabled(transcription.status != .done)
        Menu {
            Button("Texte brut (.txt)") { export(ext: "txt", content: ExportFormatter.plainText(transcription)) }
            Button("Markdown (.md)") { export(ext: "md", content: ExportFormatter.markdown(transcription)) }
        } label: {
            Label("Exporter…", systemImage: "square.and.arrow.up")
        }
        .disabled(transcription.status != .done)
    }
}
```
And the helper (import `AppKit`):
```swift
func export(ext: String, content: String) {
    let panel = NSSavePanel()
    let base = (transcription.fileName as NSString).deletingPathExtension
    panel.nameFieldStringValue = "\(base).\(ext)"
    if panel.runModal() == .OK, let url = panel.url {
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Verify build + tests** (`swift build && swift test`)

- [ ] **Step 5: Commit** — `git commit -am "feat: speaker renaming, in-transcript search, copy and export"`

---

### Task 10: App bundle script + final verification

**Files:**
- Create: `scripts/bundle.sh`, `README.md`

**Interfaces:**
- Consumes: release build of `Voxtral`.
- Produces: `build/Voxtral.app`, runnable from Finder.

- [ ] **Step 1: Write bundle script**

`scripts/bundle.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Voxtral.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp .build/release/Voxtral "$APP/Contents/MacOS/Voxtral"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Voxtral</string>
    <key>CFBundleIdentifier</key><string>com.adrienbeton.voxtral</string>
    <key>CFBundleName</key><string>Voxtral</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "OK: $APP"
```

Run: `chmod +x scripts/bundle.sh && ./scripts/bundle.sh`
Expected: `OK: build/Voxtral.app`.

- [ ] **Step 2: Write README.md**

```markdown
# Voxtral Transcription

App macOS locale : transcription + diarization de fichiers audio via l'API Mistral
(Voxtral Mini Transcribe 2), historique, lecture synchronisée audio/transcript.

## Build

​```bash
swift build          # debug
swift test           # tests
./scripts/bundle.sh  # produit build/Voxtral.app
​```

## Usage

1. Ouvrir Voxtral.app, aller dans Réglages (⌘,) et coller sa clé API Mistral.
2. Glisser un fichier audio dans la fenêtre (mp3, m4a, wav, flac…).
3. Cliquer un segment pour positionner l'audio ; ⌘F pour chercher ; renommer
   les speakers en cliquant leur nom ; Copier / Exporter depuis la toolbar.

Les fichiers audio sont référencés, pas copiés : si tu déplaces un fichier,
le transcript reste lisible mais la lecture est désactivée.
```
(remove the zero-width escapes around the code fence when writing the file)

- [ ] **Step 3: Final verification**

Run: `swift test` — all green.
Run: `open build/Voxtral.app` — app launches; verify empty state shows; open Settings (⌘,) and check the API key field renders. Close app.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: app bundle script and README"`

---

## Post-plan note for executor

Task dependencies: 1 → 2 → {3, 4} → 5 → 6 → 7 → 8 → 9 → 10. Tasks 3 and 4 are independent of each other. Tasks 2–6 are pure VoxtralCore (CLI-testable); 7–9 are UI (verify via `swift build` + smoke run); 10 is packaging.

Real-API caveat: the exact JSON field names of the diarized response (`speaker` per segment) were taken from the docs but not verified against a live call. If a real call fails to decode, print the raw JSON and adjust `TranscriptionResult` CodingKeys accordingly.
