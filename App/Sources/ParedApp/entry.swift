import Pared

@main
struct ParedApplication {
  @MainActor
  static func main() async {
    await ParedMain.main(updater: SparkleUpdateController())
  }
}
