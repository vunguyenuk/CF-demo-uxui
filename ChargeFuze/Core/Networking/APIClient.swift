import Foundation

/// A typed request: path + method + query/body, and the type the server answers with.
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    enum Method: String, Sendable { case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE" }
    var method: Method = .get
    var path: String
    var query: [URLQueryItem] = []
    var body: Data? = nil

    static func post(_ path: String, _ body: some Encodable) -> Endpoint {
        Endpoint(method: .post, path: path, body: try? APIClient.encoder.encode(body))
    }
}

/// Empty response body (204 / `{}`).
struct Empty: Decodable, Sendable {}

enum APIError: LocalizedError, Sendable {
    case http(status: Int, message: String?)
    case decoding(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .http(_, let m): m ?? "Something went wrong. Try again."
        case .decoding: "We couldn't read the server's answer."
        case .offline: "You're offline. Check your connection."
        }
    }
}

/// Thin async/await HTTP client. One instance per environment; auth token is pulled per request.
struct APIClient: Sendable {
    var baseURL: URL
    var session: URLSession = .shared
    var token: @Sendable () async -> String? = { nil }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase; e.dateEncodingStrategy = .iso8601; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; d.dateDecodingStrategy = .iso8601; return d
    }()

    func send<T>(_ endpoint: Endpoint<T>) async throws -> T {
        let req = await request(for: endpoint)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch let e as URLError where e.code == .notConnectedToInternet { throw APIError.offline }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? Self.decoder.decode([String: String].self, from: data))?["message"]
            throw APIError.http(status: status, message: msg)
        }
        if T.self == Empty.self, data.isEmpty { return Empty() as! T }
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    /// Streaming text lines (Server-Sent Events for kiosk events).
    func lines<T>(_ endpoint: Endpoint<T>) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        var req = await request(for: endpoint)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 600
        let (bytes, response) = try await session.bytes(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError.http(status: status, message: nil) }
        return bytes.lines
    }

    private func request<T>(for endpoint: Endpoint<T>) async -> URLRequest {
        var comps = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        if !endpoint.query.isEmpty { comps.queryItems = endpoint.query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let t = await token() { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }
}

extension APIClient {
    /// Base URL from Info.plist `API_BASE_URL` (set per build configuration), nil = run on mock data.
    static var configured: APIClient? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return APIClient(baseURL: url, token: { SessionStore.token })
    }
}
