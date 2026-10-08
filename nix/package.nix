{
  lib,
  stdenv,
  swift,
  swiftpm,
  fetchSwiftPMDeps,
}:
assert lib.asserts.assertMsg (
  lib.versionAtLeast swift.version "6.2.4" && lib.versionAtLeast swiftpm.version "6.2.4"
) "pared requires Swift and SwiftPM 6.2.4 or newer.";
stdenv.mkDerivation (finalAttrs: {
  pname = "pared";
  version = lib.trim (builtins.readFile ../VERSION);
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Package.resolved
      ../VERSION
      ../Sources
      ../Tests
    ];
  };
  swiftpmDeps = fetchSwiftPMDeps {
    inherit (finalAttrs) src;
    hash = "sha256-RVlAes9n7jQhkF1Z+5MUyTa3lYPuM1RwjbrJOOR6g4M=";
  };
  nativeBuildInputs = [
    swift
    swiftpm
  ];
  buildPhase = ''
    runHook preBuild
    swift build --disable-sandbox --configuration release
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    swift Tests/cli/cli.swift .build/release/pared
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 .build/release/pared "$out/bin/pared"
    cp -R .build/release/pared_Pared.bundle "$out/bin/"
    runHook postInstall
  '';
  meta = {
    description = "Disable Apple Intelligence features and remove downloaded generative models";
    mainProgram = "pared";
    platforms = lib.systems.doubles.darwin;
  };
})
