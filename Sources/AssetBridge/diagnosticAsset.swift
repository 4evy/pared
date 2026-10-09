import Foundation

/// Preserves open-ended asset metadata without exposing untyped values
public indirect enum ParedJSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case string(String)
  case integer(Int64)
  case unsignedInteger(UInt64)
  case number(Double)
  case array([Self])
  case object([String: Self])

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let bool = try? value.decode(Bool.self) {
      self = .bool(bool)
    } else if let string = try? value.decode(String.self) {
      self = .string(string)
    } else if let integer = try? value.decode(Int64.self) {
      self = .integer(integer)
    } else if let integer = try? value.decode(UInt64.self) {
      self = .unsignedInteger(integer)
    } else if let number = try? value.decode(Double.self) {
      self = .number(number)
    } else if let array = try? value.decode([Self].self) {
      self = .array(array)
    } else {
      self = .object(try value.decode([String: Self].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .null: try value.encodeNil()
    case .bool(let bool): try value.encode(bool)
    case .string(let string): try value.encode(string)
    case .integer(let integer): try value.encode(integer)
    case .unsignedInteger(let integer): try value.encode(integer)
    case .number(let number): try value.encode(number)
    case .array(let array): try value.encode(array)
    case .object(let object): try value.encode(object)
    }
  }

  public var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }
}

/// One daemon-reported asset with its decryption key removed
public struct ParedDiagnosticAsset: Codable, Sendable {
  public let location: String
  public let name: String
  public let metadata: [String: ParedJSONValue]

  private enum CodingKeys: String, CodingKey {
    case location, name, metadata
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    location = try values.decode(String.self, forKey: .location)
    name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
    var metadata = try values.decode([String: ParedJSONValue].self, forKey: .metadata)
    metadata.removeValue(forKey: "ArchiveDecryptionKey")
    self.metadata = metadata
  }
}
