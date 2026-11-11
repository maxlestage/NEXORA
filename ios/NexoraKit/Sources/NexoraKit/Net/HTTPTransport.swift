import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// L'en-tête d'une réponse HTTP : statut et en-têtes (noms en minuscules).
public struct HTTPHead: Sendable {
    public let status: Int
    public let headers: [String: String]

    public init(status: Int, headers: [String: String] = [:]) {
        self.status = status
        var h: [String: String] = [:]
        for (k, v) in headers { h[k.lowercased()] = v }
        self.headers = h
    }

    public var ok: Bool { (200..<300).contains(status) }

    init(_ response: URLResponse) {
        let http = response as? HTTPURLResponse
        var h: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { h["\(k)".lowercased()] = "\(v)" }
        self.init(status: http?.statusCode ?? 0, headers: h)
    }
}

/// Le transport HTTP : URLSession dans l'app, un faux serveur dans les tests.
public protocol HTTPTransport: Sendable {
    /// Toute la réponse d'un coup.
    func data(_ request: URLRequest) async throws -> (HTTPHead, Data)
    /// La réponse ligne par ligne, au fil de l'eau (flux SSE ou NDJSON).
    func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>)
}

/// Le transport par défaut, avec URLSession.
public struct URLSessionTransport: HTTPTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(_ request: URLRequest) async throws -> (HTTPHead, Data) {
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation : la version à rappel est la plus sûre.
        return try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let response {
                    cont.resume(returning: (HTTPHead(response), data ?? Data()))
                } else {
                    cont.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
        #else
        let (data, response) = try await session.data(for: request)
        return (HTTPHead(response), data)
        #endif
    }

    public func lines(_ request: URLRequest) async throws -> (HTTPHead, AsyncThrowingStream<String, Error>) {
        #if canImport(FoundationNetworking)
        // Pas de flux d'octets sous Linux : la réponse est lue en entier puis découpée.
        let (head, data) = try await self.data(request)
        let text = String(decoding: data, as: UTF8.self)
        return (head, AsyncThrowingStream { c in
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                c.yield(String(line))
            }
            c.finish()
        })
        #else
        let (bytes, response) = try await session.bytes(for: request)
        let stream = AsyncThrowingStream<String, Error> { c in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        c.yield(line)
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
        return (HTTPHead(response), stream)
        #endif
    }
}

extension AsyncThrowingStream where Element == String {
    /// Tout le texte restant (pour lire le corps d'une erreur).
    func joined() async -> String {
        var out: [String] = []
        do {
            for try await line in self { out.append(line) }
        } catch {}
        return out.joined(separator: "\n")
    }
}

/// Un verrou simple pour partager un petit état entre tâches.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ v: Value) {
        lock.lock()
        value = v
        lock.unlock()
    }

    @discardableResult
    func update<R>(_ f: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return f(&value)
    }
}
