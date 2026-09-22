{
  lib,
  buildNpmPackage,
  nodejs_24,
  optionsJSON,
  revision ? "main",
}:
buildNpmPackage {
  pname = "pared-docs";
  version = "1.0.0";
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../package.json
      ../package-lock.json
      ./site/index.html
      ../tsconfig.json
      ../vite.config.ts
      ./site/src
      ./site/scripts
      (lib.fileset.difference ./site/public (lib.fileset.maybeMissing ./site/public/options.json))
    ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-7EYRSEsmgZJe4FpE98DSc4yZRT0xmEJIkdoe+aowhP8=";
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
