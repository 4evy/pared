import CryptoKit
import Foundation

/// Sanitized failures that never include raw catalog metadata
public enum ParedCatalogDecodingError: LocalizedError, Sendable {
  case envelope, encoding, header, payload, audience

  public var errorDescription: String? {
    switch self {
    case .envelope: "Apple returned an unsupported catalog envelope"
    case .encoding: "Apple returned an unsupported catalog encoding"
    case .header: "Apple returned unsupported catalog header parameters"
    case .payload: "Apple returned an unsupported catalog payload"
    case .audience: "Apple returned a catalog for an unexpected audience"
    }
  }
}

public struct ParedCatalogAssetIdentity: Hashable, Sendable {
  public let type: String
  public let specifier: String
  public let version: String
  public let archive: String

  public init?(_ metadata: [String: ParedJSONValue]) {
    guard let type = metadata["AssetType"]?.stringValue,
      let specifier = metadata["AssetSpecifier"]?.stringValue,
      let version = metadata["AssetVersion"]?.stringValue,
      let archive = metadata["ArchiveID"]?.stringValue,
      !type.isEmpty, !specifier.isEmpty, !version.isEmpty, !archive.isEmpty
    else { return nil }
    self.type = type
    self.specifier = specifier
    self.version = version
    self.archive = archive
  }
}

public struct ParedCatalogRequestBody: Encodable, Sendable {
  public let assetType: String
  public let audience: String
  public let productType: String
  public let hardwareModel: String
  public let productVersion: String
  public let buildVersion: String
  public let purpose = "auto"
  public let clientVersion = 2
  public let compatibilityVersion = 20
  // The daemon sends CertIssuanceDay only after its Pallas verifier learns a
  // certificate issuance date. This stateless HTTPS client has no such date

  private enum CodingKeys: String, CodingKey {
    case assetType = "AssetType"
    case audience = "AssetAudience"
    case productType = "ProductType"
    case hardwareModel = "HWModelStr"
    case productVersion = "ProductVersion"
    case buildVersion = "BuildVersion"
    case purpose = "Purpose"
    case clientVersion = "ClientVersion"
    case compatibilityVersion = "CompatibilityVersion"
  }

  public init(assetType: String, configuration: ParedCatalogRequestConfiguration) {
    self.assetType = assetType
    audience = configuration.audience
    productType = configuration.productType
    hardwareModel = configuration.hardwareModel
    productVersion = configuration.productVersion
    buildVersion = configuration.buildVersion
  }
}

public struct ParedCatalogPublishedAsset: Decodable, Sendable {
  public let identity: ParedCatalogAssetIdentity
  public let metadata: [String: ParedJSONValue]

  public init(from decoder: any Decoder) throws {
    var metadata = try decoder.singleValueContainer().decode([String: ParedJSONValue].self)
    metadata.removeValue(forKey: "ArchiveDecryptionKey")
    guard let identity = ParedCatalogAssetIdentity(metadata) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath, debugDescription: "Incomplete catalog asset identity"))
    }
    self.identity = identity
    self.metadata = metadata
  }
}

/// Published metadata parsed from an HTTPS response, with keys redacted
/// Envelope parsing checks its format and audience, not its cryptographic
/// signature or the existence of any corresponding local files
public struct ParedPublishedCatalog: Decodable, Sendable {
  public let audience: String
  public let assets: [ParedCatalogPublishedAsset]
  public let assetSetID: String?
  public let postingDate: String?

  private enum CodingKeys: String, CodingKey {
    case audience = "AssetAudience"
    case assets = "Assets"
    case assetSetID = "AssetSetId"
    case postingDate = "PostingDate"
  }

  public init(envelope: Data, audience: String) throws {
    // Parse compact JWS strictly; HTTPS authenticates the configured host
    // This does not verify the envelope's independent signature
    let parts = envelope.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
    guard parts.count == 3 else {
      throw ParedCatalogDecodingError.envelope
    }
    func decoded(_ part: Data.SubSequence) throws -> Data {
      guard !part.isEmpty else { throw ParedCatalogDecodingError.encoding }
      var encoded = String(decoding: part, as: UTF8.self)
        .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
      guard let data = Data(base64Encoded: encoded) else {
        throw ParedCatalogDecodingError.encoding
      }
      // Reject noncanonical unused bits rather than accepting alternate
      // spellings
      let canonical = data.base64EncodedString(options: [.base64URLAlphabet, .omitPaddingCharacter])
      guard canonical == String(decoding: part, as: UTF8.self) else {
        throw ParedCatalogDecodingError.encoding
      }
      return data
    }
    enum Algorithm: String, Decodable {
      case es256 = "ES256"
      case es384 = "ES384"

      // Pallas selects SecKey's ECDSA message-X962 algorithms: Apple's compact
      // envelope carries DER integers, unlike JWS's fixed-width R || S format
      // Check that shape without claiming cryptographic verification
      func acceptsSignatureShape(_ signature: Data) -> Bool {
        do {
          let raw: Data
          let canonical: Data
          switch self {
          case .es256:
            let parsed = try P256.Signing.ECDSASignature(derRepresentation: signature)
            raw = parsed.rawRepresentation
            canonical = parsed.derRepresentation
          case .es384:
            let parsed = try P384.Signing.ECDSASignature(derRepresentation: signature)
            raw = parsed.rawRepresentation
            canonical = parsed.derRepresentation
          }
          // CryptoKit parses DER and bounds the scalars; require canonical
          // encoding and positive scalars, since it also permits zero
          return canonical == signature && raw.prefix(raw.count / 2).contains { $0 != 0 }
            && raw.suffix(raw.count / 2).contains { $0 != 0 }
        } catch {
          return false
        }
      }
    }
    struct Header: Decodable {
      let alg: Algorithm

      private enum CodingKeys: String, CodingKey { case alg, crit, b64 }

      init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alg = try values.decode(Algorithm.self, forKey: .alg)
        // Presence matters: null must not bypass an unsupported parameter
        guard !values.contains(.crit) else { throw ParedCatalogDecodingError.header }
        if values.contains(.b64), try !values.decode(Bool.self, forKey: .b64) {
          throw ParedCatalogDecodingError.header
        }
      }
    }
    let headerData = try decoded(parts[0])
    let payload = try decoded(parts[1])
    let signature = try decoded(parts[2])
    let header: Header
    do { header = try JSONDecoder().decode(Header.self, from: headerData) } catch {
      throw ParedCatalogDecodingError.header
    }
    guard header.alg.acceptsSignatureShape(signature) else {
      throw ParedCatalogDecodingError.envelope
    }
    do {
      self = try JSONDecoder().decode(Self.self, from: payload)
    } catch {
      // Do not echo raw metadata or decoder values into the exported report
      throw ParedCatalogDecodingError.payload
    }
    guard self.audience == audience else {
      throw ParedCatalogDecodingError.audience
    }
  }
}
