import CryptoKit
import Flutter
import Foundation
import NetworkExtension
import Security

final class EnrollmentChannel {
  private enum EnrollmentError: Error {
    case invalidArguments
    case secureStorageFailed
    case expiredSession
  }

  private struct EphemeralKey {
    let privateKey: P256.KeyAgreement.PrivateKey
    let expiresAt: TimeInterval
  }

  private var ephemeralKeys: [String: EphemeralKey] = [:]
  private let profileQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "net.piagent.enrollment.profile",
    kSecAttrAccount as String: "v1",
  ]

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "publicKey":
        let alias = try identityAlias(arguments)
        let privateKey = try identityKey(alias, create: true)
        guard let key = SecKeyCopyPublicKey(privateKey),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
          throw EnrollmentError.secureStorageFailed
        }
        result(FlutterStandardTypedData(bytes: raw))
      case "sign":
        let privateKey = try identityKey(identityAlias(arguments), create: false)
        let data = try bytes(arguments, "data")
        guard let signature = SecKeyCreateSignature(
          privateKey, .ecdsaSignatureMessageX962SHA256, data as CFData, nil
        ) as Data? else {
          throw EnrollmentError.secureStorageFailed
        }
        result(FlutterStandardTypedData(bytes: signature))
      case "verify":
        let publicKey = try bytes(arguments, "publicKey")
        let data = try bytes(arguments, "data")
        let der = try bytes(arguments, "signature")
        result(verify(publicKey, data: data, der: der))
      case "ephemeralPublicKey":
        let session = try sessionId(arguments)
        result(FlutterStandardTypedData(bytes: try ephemeralPublicKey(session)))
      case "discardEphemeral":
        ephemeralKeys.removeValue(forKey: try sessionId(arguments))
        result(nil)
      case "decrypt":
        let session = try sessionId(arguments)
        result(FlutterStandardTypedData(bytes: try decrypt(session, arguments)))
      case "saveProfile":
        try saveProfile(string(arguments, "data"))
        result(nil)
      case "loadProfile":
        result(try loadProfile())
      case "connectWifi":
        let ssid = try string(arguments, "ssid")
        let password = try string(arguments, "password")
        connectWifi(ssid, password: password, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "enrollment_failed", message: "手机安全存储或注册操作失败。", details: nil
      ))
    }
  }

  private func string(_ arguments: [String: Any], _ key: String) throws -> String {
    guard let value = arguments[key] as? String else { throw EnrollmentError.invalidArguments }
    return value
  }

  private func bytes(_ arguments: [String: Any], _ key: String) throws -> Data {
    guard let value = arguments[key] as? FlutterStandardTypedData else {
      throw EnrollmentError.invalidArguments
    }
    return value.data
  }

  private func identityAlias(_ arguments: [String: Any]) throws -> Data {
    let alias = try string(arguments, "alias")
    guard alias.range(of: #"\A[A-Za-z0-9_.-]{1,160}\z"#, options: .regularExpression) != nil else {
      throw EnrollmentError.invalidArguments
    }
    return Data("net.piagent.enrollment.identity.\(alias)".utf8)
  }

  private func sessionId(_ arguments: [String: Any]) throws -> String {
    let session = try string(arguments, "session")
    guard session.range(of: #"\A[A-Za-z0-9_-]{1,128}\z"#, options: .regularExpression) != nil else {
      throw EnrollmentError.invalidArguments
    }
    return session
  }

  private func identityKey(_ tag: Data, create: Bool) throws -> SecKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess, let item = item, CFGetTypeID(item) == SecKeyGetTypeID() {
      return item as! SecKey
    }
    guard create, status == errSecItemNotFound else { throw EnrollmentError.secureStorageFailed }
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      ],
    ]
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else {
      throw EnrollmentError.secureStorageFailed
    }
    return key
  }

  private func verify(_ raw: Data, data: Data, der: Data) -> Bool {
    guard raw.count == 65, raw.first == 4,
          let publicKey = try? P256.Signing.PublicKey(x963Representation: raw),
          let signature = try? P256.Signing.ECDSASignature(derRepresentation: der) else {
      return false
    }
    return publicKey.isValidSignature(signature, for: data)
  }

  private func ephemeralPublicKey(_ session: String) throws -> Data {
    let now = ProcessInfo.processInfo.systemUptime
    ephemeralKeys = ephemeralKeys.filter { $0.value.expiresAt > now }
    guard ephemeralKeys[session] == nil, ephemeralKeys.count < 4 else {
      throw EnrollmentError.invalidArguments
    }
    let key = P256.KeyAgreement.PrivateKey(compactRepresentable: false)
    ephemeralKeys[session] = EphemeralKey(privateKey: key, expiresAt: now + 120)
    return key.publicKey.x963Representation
  }

  private func decrypt(_ session: String, _ arguments: [String: Any]) throws -> Data {
    guard let key = ephemeralKeys.removeValue(forKey: session),
          key.expiresAt > ProcessInfo.processInfo.systemUptime else {
      throw EnrollmentError.expiredSession
    }
    let raw = try bytes(arguments, "serverPublicKey")
    let salt = try bytes(arguments, "salt")
    let sealed = try bytes(arguments, "sealed")
    guard raw.count == 65, raw.first == 4, salt.count == 32, sealed.count >= 28 else {
      throw EnrollmentError.invalidArguments
    }
    let publicKey = try P256.KeyAgreement.PublicKey(x963Representation: raw)
    let shared = try key.privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    let symmetricKey = shared.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: salt,
      sharedInfo: Data("piagent/enrollment/response/v1".utf8),
      outputByteCount: 32
    )
    return try AES.GCM.open(
      AES.GCM.SealedBox(combined: sealed),
      using: symmetricKey,
      authenticating: bytes(arguments, "associatedData")
    )
  }

  private func saveProfile(_ profile: String) throws {
    let value = Data(profile.utf8)
    let update: [String: Any] = [kSecValueData as String: value]
    let status = SecItemUpdate(profileQuery as CFDictionary, update as CFDictionary)
    if status == errSecSuccess { return }
    guard status == errSecItemNotFound else { throw EnrollmentError.secureStorageFailed }
    var attributes = profileQuery
    attributes[kSecValueData as String] = value
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
      throw EnrollmentError.secureStorageFailed
    }
  }

  private func loadProfile() throws -> String? {
    var query = profileQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let bytes = item as? Data,
          let profile = String(data: bytes, encoding: .utf8) else {
      throw EnrollmentError.secureStorageFailed
    }
    return profile
  }

  private func connectWifi(_ ssid: String, password: String, result: @escaping FlutterResult) {
    let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
    configuration.joinOnce = false
    NEHotspotConfigurationManager.shared.apply(configuration) { error in
      let hotspotError = error as NSError?
      let alreadyAssociated = hotspotError?.domain == NEHotspotConfigurationErrorDomain
        && hotspotError?.code == NEHotspotConfigurationError.alreadyAssociated.rawValue
      DispatchQueue.main.async { result(error == nil || alreadyAssociated) }
    }
  }
}
