{
  lib,
  pkgs,
  policyFile,
  package,
  stateDirectory,
  profilePath,
}:
let
  coreutils = "${pkgs.coreutils}/bin";
in
''
  (
    set -e
    echo ${lib.escapeShellArg "Install ${profilePath} to block model downloads."}
    paredState=${lib.escapeShellArg stateDirectory}
    ${coreutils}/install -d -m 0700 "$paredState"
    if ! ${pkgs.diffutils}/bin/cmp -s ${policyFile} "$paredState/cleaned-policy.json"; then
      echo "Removing disabled Apple Intelligence models with pared..."
      if ${lib.getExe package} models cleanup --policy ${policyFile}; then
        ${coreutils}/cp ${policyFile} "$paredState/cleaned-policy.json.tmp"
        ${coreutils}/mv -f "$paredState/cleaned-policy.json.tmp" "$paredState/cleaned-policy.json"
      else
        echo "pared cleanup failed; the next activation will retry." >&2
      fi
    fi
  )
''
