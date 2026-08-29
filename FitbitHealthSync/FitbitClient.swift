import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class FitbitClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let session: URLSession
    private var webSession: ASWebAuthenticationSession?
    private(set) var token: FitbitToken? = KeychainStore.load()

    init(session: URLSession = .shared) { self.session = session }

    func authorize() async throws {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "FITBIT_CLIENT_ID") as? String,
              !clientID.isEmpty, !clientID.contains("replace_with") else { throw SyncError.missingConfiguration }
        let redirect = (Bundle.main.object(forInfoDictionaryKey: "FITBIT_REDIRECT_URI") as? String) ?? "fitbithealthsync://oauth/callback"
        let verifier = Self.base64URL(Data((0..<64).map { _ in UInt8.random(in: 0...255) }))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var parts = URLComponents(string: "https://www.fitbit.com/oauth2/authorize")!
        parts.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: "activity heartrate sleep weight nutrition oxygen_saturation respiratory_rate temperature cardio_fitness")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: URL(string: redirect)?.scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? SyncError.authenticationFailed) }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = true
            webSession = auth
            auth.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { throw SyncError.authenticationFailed }
        var request = URLRequest(url: URL(string: "https://api.fitbit.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["client_id": clientID, "code": code, "code_verifier": verifier, "grant_type": "authorization_code", "redirect_uri": redirect])
        token = try await exchange(request)
    }

    func disconnect() { token = nil; KeychainStore.clear() }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await refreshIfNeeded()
        guard let token else { throw SyncError.notConnected }
        var request = URLRequest(url: URL(string: "https://api.fitbit.com/1/user/-/\(path)")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SyncError.apiFailure(String(data: data, encoding: .utf8) ?? "Fitbit request failed") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func refreshIfNeeded() async throws {
        guard let old = token, old.expiresAt < Date().addingTimeInterval(60) else { return }
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "FITBIT_CLIENT_ID") as? String else { throw SyncError.missingConfiguration }
        var request = URLRequest(url: URL(string: "https://api.fitbit.com/oauth2/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["grant_type": "refresh_token", "refresh_token": old.refreshToken, "client_id": clientID])
        token = try await exchange(request)
    }

    private func exchange(_ request: URLRequest) async throws -> FitbitToken {
        struct Response: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double; let user_id: String }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SyncError.authenticationFailed }
        let value = try JSONDecoder().decode(Response.self, from: data)
        let token = FitbitToken(accessToken: value.access_token, refreshToken: value.refresh_token, expiresAt: Date().addingTimeInterval(value.expires_in), userID: value.user_id)
        try KeychainStore.save(token); return token
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func base64URL(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func form(_ values: [String: String]) -> Data? { values.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }.joined(separator: "&").data(using: .utf8) }
}

enum SyncError: LocalizedError {
    case missingConfiguration, authenticationFailed, notConnected, healthUnavailable, apiFailure(String)
    var errorDescription: String? {
        switch self {
        case .missingConfiguration: "Add your Fitbit client ID in Configuration.xcconfig."
        case .authenticationFailed: "Fitbit sign-in could not be completed."
        case .notConnected: "Connect a Fitbit account first."
        case .healthUnavailable: "Apple Health is not available on this device."
        case .apiFailure(let detail): "Fitbit API error: \(detail)"
        }
    }
}
