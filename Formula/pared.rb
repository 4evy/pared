class Pared < Formula
  desc "Control Apple Intelligence features and remove downloaded generative models"
  homepage "https://github.com/4evy/pared"
  url "https://github.com/4evy/pared.git", tag: "1.0.0"
  head "https://github.com/4evy/pared.git", branch: "master"

  depends_on xcode: ["27.0", :build]
  depends_on macos: :golden_gate

  def install
    system "swift", "build", *std_swift_args
    # Keep the resource bundle beside the executable after the build tree is removed
    libexec.install ".build/release/pared", ".build/release/pared_Pared.bundle"
    bin.install_symlink libexec/"pared"
  end
end
