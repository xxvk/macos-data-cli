import Foundation
import CryptoKit

enum RESTDiagnosticSummary {
    static func make(route: RESTRouteDescriptor, params: String, body: String?) -> String {
        let paramsData = Data(params.utf8)
        let bodyData = body.map { Data($0.utf8) }
        let bodyFields = bodyData.map { " bodyBytes=\($0.count) bodySHA256=\(sha256($0))" } ?? " bodyBytes=0"
        return "route=\(route.method.rawValue) \(route.path) paramsBytes=\(paramsData.count) paramsSHA256=\(sha256(paramsData))\(bodyFields)"
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
