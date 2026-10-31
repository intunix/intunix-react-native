import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

package let apiPath = "/nikonudge/api/v1"
package let channel = "mobile_sdk"

package struct HttpError: Error { package let status: Int }

package struct HttpResponse { package let status: Int; package let body: Data?; package let etag: String? }

package final class Http {
    private let apiHost: String, apiKey: String, sdkHeader: String
    private let session: URLSession

    package init(apiHost: String, apiKey: String, sdkHeader: String, session: URLSession = .shared) {
        self.apiHost = apiHost; self.apiKey = apiKey; self.sdkHeader = sdkHeader; self.session = session
    }

    /// Throws HttpError on non-2xx; 304 is returned, not thrown.
    package func request(_ method: String, _ path: String, body: Any? = nil, etag: String? = nil) async throws -> HttpResponse {
        guard let url = URL(string: apiHost + apiPath + path) else { throw HttpError(status: 0) }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-client-key")
        req.setValue(sdkHeader, forHTTPHeaderField: "x-intunix-sdk")
        if let etag { req.setValue(etag, forHTTPHeaderField: "if-none-match") }
        if let body { req.httpBody = Data(jsonString(body).utf8) }
        let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
            session.dataTask(with: req) { d, r, e in
                if let e { cont.resume(throwing: e) } else if let r { cont.resume(returning: (d ?? Data(), r)) }
                else { cont.resume(throwing: HttpError(status: 0)) }
            }.resume()
        }
        guard let http = response as? HTTPURLResponse else { throw HttpError(status: 0) }
        if http.statusCode == 304 { return HttpResponse(status: 304, body: nil, etag: etag) }
        guard (200..<300).contains(http.statusCode) else { throw HttpError(status: http.statusCode) }
        let tag = http.allHeaderFields.first { ($0.key as? String)?.lowercased() == "etag" }?.value as? String
        return HttpResponse(status: http.statusCode, body: data, etag: tag)
    }
}

/// Two retries with jittered backoff; 4xx never retries. Same policy as @intunix/core retry().
package func retry<T>(retries: Int = 2, baseMs: UInt64 = 500, maxMs: UInt64 = 10_000, _ block: () async throws -> T) async throws -> T {
    var attempt = 0
    while true {
        do { return try await block() } catch let e as HttpError where (400..<500).contains(e.status) {
            throw e
        } catch {
            if attempt == retries { throw error }
        }
        let d = min(maxMs, baseMs << UInt64(attempt))
        try? await Task.sleep(nanoseconds: UInt64(Double(d) * (0.5 + Double.random(in: 0..<0.5))) * 1_000_000)
        attempt += 1
    }
}
