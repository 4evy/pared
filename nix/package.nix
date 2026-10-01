{
  lib,
  stdenv,
  swift,
  swiftpm,
  python3,
}:
assert lib.asserts.assertMsg (
  lib.versionAtLeast swift.version "6.2.4" && lib.versionAtLeast swiftpm.version "6.2.4"
) "pared requires Swift and SwiftPM 6.2.4 or newer.";
stdenv.mkDerivation {
  pname = "pared";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Package.swift
      ../Sources
      ../Tests
    ];
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
  nativeCheckInputs = [ python3 ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 Tests/test_cli.py .build/release/pared
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
}
