import Foundation
import Security
import LocalAuthentication
import Darwin

struct ClaudeCredentials: Sendable {
    let accessToken: String
}

enum ClaudeConnectionError: Error, Equatable {
    case signInRequired
    case keychainAccessRequired
    case unsupportedConfiguration
    case invalidCredentials
    case unavailable
    case rateLimited(TimeInterval)

    var message: String {
        switch self {
        case .signInRequired: "Sign in with Claude Code"
        case .keychainAccessRequired: "Connect Claude to allow Keychain access"
        case .unsupportedConfiguration: "Custom Claude configuration is unsupported"
        case .invalidCredentials: "Claude sign-in needs renewal"
        case .unavailable: "Claude quota unavailable"
        case .rateLimited: "Claude refresh temporarily rate limited"
        }
    }
}

struct ClaudeAuthReader: Sendable {
    static let maximumSize = 1_048_576
    let homeDirectory: URL
    let environment: [String: String]

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func read(allowInteraction: Bool = false) throws -> ClaudeCredentials {
        // Custom config directories use distinct Keychain identities. Never fall
        // through to another account when one has been explicitly selected.
        guard environment["CLAUDE_CONFIG_DIR"].map({ $0.isEmpty }) ?? true else {
            throw ClaudeConnectionError.unsupportedConfiguration
        }
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try Self.parse(data)
        }
        guard status == errSecItemNotFound else {
            throw ClaudeConnectionError.keychainAccessRequired
        }
        return try Self.parse(Self.readFallback(at: homeDirectory.appendingPathComponent(".claude/.credentials.json")))
    }

    static func readFallback(at url: URL) throws -> Data {
        // Nonblocking open avoids hanging on a FIFO before fstat can reject it.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ClaudeConnectionError.signInRequired }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(handle.fileDescriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size <= Self.maximumSize else {
            throw ClaudeConnectionError.invalidCredentials
        }
        var data = Data()
        while data.count <= Self.maximumSize {
            let count = min(65_536, Self.maximumSize + 1 - data.count)
            guard let part = try handle.read(upToCount: count), !part.isEmpty else { break }
            data.append(part)
        }
        return data
    }

    static func parse(_ data: Data, now: Date = .now) throws -> ClaudeCredentials {
        struct Envelope: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let expiresAt: Double
                let scopes: [String]
            }
            let claudeAiOauth: OAuth
        }
        guard data.count <= maximumSize,
              let auth = try? JSONDecoder().decode(Envelope.self, from: data).claudeAiOauth,
              !auth.accessToken.isEmpty, auth.accessToken.utf8.count <= 16_384,
              auth.accessToken.utf8.allSatisfy({ (33...126).contains($0) }),
              auth.scopes.contains("user:profile"),
              auth.expiresAt.isFinite else {
            throw ClaudeConnectionError.invalidCredentials
        }
        guard auth.expiresAt / 1_000 > now.timeIntervalSince1970 else {
            throw ClaudeConnectionError.signInRequired
        }
        return ClaudeCredentials(accessToken: auth.accessToken)
    }
}
