import CryptoKit
import XCTest
@testable import Steneo

/// Verifies the AES-GCM primitive used to encrypt history at rest. Uses an
/// injected key (the static seam) so the tests never touch the Keychain.
@MainActor
final class EncryptionServiceTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)

    func testRoundTrip() {
        let original = "Steneo secret 🔐 äöü ß".data(using: .utf8)!
        guard let cipher = EncryptionService.seal(original, with: key) else {
            return XCTFail("seal returned nil")
        }
        XCTAssertNotEqual(cipher, original, "ciphertext must differ from plaintext")
        XCTAssertEqual(EncryptionService.open(cipher, with: key), original)
    }

    func testEmptyDataRoundTrips() {
        let empty = Data()
        guard let cipher = EncryptionService.seal(empty, with: key) else {
            return XCTFail("seal(empty) returned nil")
        }
        XCTAssertEqual(EncryptionService.open(cipher, with: key), empty)
    }

    func testWrongKeyFailsToDecrypt() {
        let cipher = EncryptionService.seal(Data("data".utf8), with: key)!
        XCTAssertNil(EncryptionService.open(cipher, with: SymmetricKey(size: .bits256)))
    }

    func testTamperedCiphertextFailsToDecrypt() {
        var cipher = EncryptionService.seal(Data("data".utf8), with: key)!
        cipher[cipher.count - 1] ^= 0xFF   // flip a bit in the auth tag
        XCTAssertNil(EncryptionService.open(cipher, with: key))
    }

    func testGarbageFailsToDecrypt() {
        XCTAssertNil(EncryptionService.open(Data([0, 1, 2, 3]), with: key))
    }

    func testNonceMakesCiphertextNonDeterministic() {
        // AES-GCM uses a fresh random nonce, so the same plaintext seals differently.
        let d = Data("repeatable".utf8)
        XCTAssertNotEqual(EncryptionService.seal(d, with: key),
                          EncryptionService.seal(d, with: key))
    }
}
