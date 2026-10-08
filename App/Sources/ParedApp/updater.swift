import Combine
import Foundation
import Pared
import Sparkle

@MainActor
final class SparkleUpdateController: NSObject, ParedUpdateControlling, SPUUpdaterDelegate {
  private var controller: SPUStandardUpdaterController?
  private var readiness: (@MainActor () -> Bool)?
  private var pendingRelaunch: (() -> Void)?
  private var observation: AnyCancellable?

  var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }
  var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

  var automaticallyChecksForUpdates: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set { controller?.updater.automaticallyChecksForUpdates = newValue }
  }

  var automaticallyDownloadsUpdates: Bool {
    get { controller?.updater.automaticallyDownloadsUpdates ?? false }
    set { controller?.updater.automaticallyDownloadsUpdates = newValue }
  }

  func start(
    readiness: @escaping @MainActor () -> Bool,
    stateChanged: @escaping @MainActor () -> Void
  ) throws {
    guard controller == nil else { return }
    let loaded = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.readiness = readiness
    try loaded.updater.start()
    controller = loaded
    let updater = loaded.updater
    observation = Publishers.CombineLatest4(
      updater.publisher(for: \.canCheckForUpdates),
      updater.publisher(for: \.automaticallyChecksForUpdates),
      updater.publisher(for: \.automaticallyDownloadsUpdates),
      updater.publisher(for: \.lastUpdateCheckDate)
    )
    .sink { _ in
      Task { @MainActor in stateChanged() }
    }
  }

  func checkForUpdates() {
    guard readiness?() == true, canCheckForUpdates else { return }
    controller?.checkForUpdates(nil)
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    guard readiness?() == true else {
      throw NSError(
        domain: "org.pared.updater", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Finish the current operation and save or discard your changes before updating."
        ])
    }
  }

  func updater(
    _ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    guard readiness?() != true else { return false }
    pendingRelaunch = installHandler
    return true
  }

  func resumeIfReady() {
    guard let handler = pendingRelaunch, readiness?() == true else { return }
    pendingRelaunch = nil
    handler()
  }
}
