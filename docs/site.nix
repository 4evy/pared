{
  lib,
  buildNpmPackage,
  nodejs_24,
  optionsJSON,
  revision ? "master",
}:
buildNpmPackage {
  pname = "pared-docs";
  version = lib.trim (builtins.readFile ../VERSION);
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../package.json
      ../package-lock.json
      ./site/index.html
      ./site/docs
      ../tsconfig.json
      ../vite.config.ts
      ./site/src
      ./site/scripts
      (lib.fileset.difference ./site/public (lib.fileset.maybeMissing ./site/public/options.json))
    ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-1RNQtlRcPGLMyT7sfk5GNhUrIf2ee2INcguY5cKQ5FM=";
  env.PARED_REVISION = revision;
  env.PARED_OPTIONS_JSON = "${optionsJSON}/share/doc/nixos/options.json";
  preBuild = "npm run check";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/doc/pared"
    cp -r docs/site/dist/. "$out/share/doc/pared/"
    runHook postInstall
  '';
}
