import Foundation

enum AnalyticsValue: Codable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum AnalyticsClient {
    private static let dispatcher = AnalyticsDispatcher()

    static func track(_ event: String, properties: [String: AnalyticsValue] = [:]) {
        Task(priority: .utility) {
            await dispatcher.enqueue(event: event, properties: properties)
        }
    }
}

private actor AnalyticsDispatcher {
    private struct Event: Codable, Sendable {
        let projectKey: String
        let anonymousID: String
        let eventID: String
        let event: String
        let timestamp: String
        let sessionID: String
        let properties: [String: AnalyticsValue]
        let context: [String: AnalyticsValue]

        enum CodingKeys: String, CodingKey {
            case projectKey = "project_key"
            case anonymousID = "anonymous_id"
            case eventID = "event_id"
            case event
            case timestamp
            case sessionID = "session_id"
            case properties
            case context
        }
    }

    private static let endpoint = URL(string: "https://dvz-analytics.netlify.app/api/events")!
    private static let projectKey = "JLIl2tlAKvOd"
    private static let pendingEventsKey = "dvz_analytics_pending_events"
    private static let anonymousIDKey = "dvz_analytics_anonymous_id"
    private static let maximumPendingEvents = 100
    private static let maximumRetryDelay: TimeInterval = 60

    private let sessionID = UUID().uuidString
    private let anonymousID: String
    private var pendingEvents: [Event]
    private var isFlushing = false
    private var retryAttempt = 0

    init() {
        let defaults = UserDefaults.standard
        if let existingID = defaults.string(forKey: Self.anonymousIDKey) {
            anonymousID = existingID
        } else {
            let newID = UUID().uuidString
            defaults.set(newID, forKey: Self.anonymousIDKey)
            anonymousID = newID
        }

        if let data = defaults.data(forKey: Self.pendingEventsKey),
           let events = try? JSONDecoder().decode([Event].self, from: data) {
            pendingEvents = events
        } else {
            pendingEvents = []
        }
    }

    func enqueue(event: String, properties: [String: AnalyticsValue]) async {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let appBuild = info?["CFBundleVersion"] as? String ?? "unknown"

        pendingEvents.append(
            Event(
                projectKey: Self.projectKey,
                anonymousID: anonymousID,
                eventID: UUID().uuidString,
                event: event,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                sessionID: sessionID,
                properties: properties,
                context: [
                    "platform": .string("macos"),
                    "app_version": .string(appVersion),
                    "app_build": .string(appBuild)
                ]
            )
        )

        if pendingEvents.count > Self.maximumPendingEvents {
            pendingEvents.removeFirst(pendingEvents.count - Self.maximumPendingEvents)
        }
        persistPendingEvents()

        guard !isFlushing else { return }
        isFlushing = true
        await flush()
    }

    private func flush() async {
        defer { isFlushing = false }

        while let event = pendingEvents.first {
            do {
                var request = URLRequest(url: Self.endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(event)
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    scheduleRetry()
                    return
                }

                switch httpResponse.statusCode {
                case 200..<300:
                    pendingEvents.removeFirst()
                    retryAttempt = 0
                    persistPendingEvents()
                case 429, 503:
                    scheduleRetry(retryAfter: httpResponse.value(forHTTPHeaderField: "Retry-After"))
                    return
                case 400..<500:
                    // A malformed event will never succeed. Drop it rather than
                    // blocking every later event in the persistent queue.
                    pendingEvents.removeFirst()
                    retryAttempt = 0
                    persistPendingEvents()
                default:
                    scheduleRetry()
                    return
                }
            } catch {
                scheduleRetry()
                return
            }
        }
    }

    private func scheduleRetry(retryAfter: String? = nil) {
        let serverDelay = retryAfter.flatMap(TimeInterval.init)
        let exponentialDelay = min(pow(2, Double(retryAttempt)), Self.maximumRetryDelay)
        let delay = min(max(serverDelay ?? exponentialDelay, 1), Self.maximumRetryDelay)
        retryAttempt += 1

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await retryPendingEvents()
        }
    }

    private func retryPendingEvents() async {
        guard !isFlushing, !pendingEvents.isEmpty else { return }
        isFlushing = true
        await flush()
    }

    private func persistPendingEvents() {
        if pendingEvents.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.pendingEventsKey)
        } else if let data = try? JSONEncoder().encode(pendingEvents) {
            UserDefaults.standard.set(data, forKey: Self.pendingEventsKey)
        }
    }
}
