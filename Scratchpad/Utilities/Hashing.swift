import CryptoKit
import Foundation

enum Hashing {
    static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
