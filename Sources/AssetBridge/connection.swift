import Foundation

private final class BridgeServiceConnection {
  private let connection: NSXPCConnection
  private let errorHandler: @Sendable (Error) -> Void

  init(interface: NSXPCInterface, errorHandler: @escaping @Sendable (Error) -> Void) {
    self.errorHandler = errorHandler
    connection = NSXPCConnection(
      machServiceName: "com.apple.siri.uaf.subscription.service", options: [])
    connection.remoteObjectInterface = interface
    connection.resume()
  }

  deinit { connection.invalidate() }

  func proxy() -> NSObject? {
    connection.remoteObjectProxyWithErrorHandler(errorHandler) as? NSObject
  }

  func invalidate() { connection.invalidate() }
}

/// An operation connection with Apple's checked signatures and allowed classes
/// Transport errors reach errorHandler and can follow daemon effects
public final class ParedOperationService {
  private let connection: BridgeServiceConnection

  public init?(errorHandler: @escaping @Sendable (Error) -> Void) {
    guard let interface = paredServiceInterface() else { return nil }
    connection = BridgeServiceConnection(interface: interface, errorHandler: errorHandler)
  }

  func proxy() -> NSObject? { connection.proxy() }

  /// Keep the service alive through its reply or timeout, then invalidate it
  public func invalidate() { connection.invalidate() }
}

/// A read-only diagnostic connection with Apple's checked reply interface
public final class ParedDiagnosticService {
  private let connection: BridgeServiceConnection

  public init?(errorHandler: @escaping @Sendable (Error) -> Void) {
    guard let interface = paredDiagnosticServiceInterface() else {
      return nil
    }
    connection = BridgeServiceConnection(interface: interface, errorHandler: errorHandler)
  }

  func proxy() -> NSObject? { connection.proxy() }

  /// Keep the service alive through its reply or timeout, then invalidate it
  public func invalidate() { connection.invalidate() }
}
