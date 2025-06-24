{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  systemBuilder = ''
    mkdir -p $out/{tmp,opt,var,run}
    copyAll() {
      while IFS= read -rd "" f; do
        rel="$(realpath --no-symlinks --relative-to="$1" "$f")"
        if [[ "$rel" = '.' ]]; then
          dst="$out$2"
        else
          dst="$out$2/$rel"
        fi
        if [ -d "$f" ]; then
          [ -d "$dst" ] || mkdir "$dst"
        else
          if [ -e "$dst" ]; then
            echo "duplicated file $f -> $dst" >&2
            exit 1
          fi
          cp "$f" "$dst"
        fi
      done
    }

    find "${config.system.build.etc}/etc" -print0 | copyAll "${config.system.build.etc}/etc" /etc
    find "${config.system.path}/etc" -print0 | copyAll "${config.system.path}/etc" /etc

    mkdir $out/usr
    while IFS= read -rd "" f; do
      ln -s "${config.system.path}/$f" $out/usr/
    done < <(ls -A --zero "${config.system.path}" | sed --zero '/^etc$/d')

    ln -s /run $out/var/run
  '';

  baseSystem = pkgs.stdenvNoCC.mkDerivation {
    name = "nixos-container";
    preferLocalBuild = true;
    allowSubstitutes = false;
    buildCommand = systemBuilder;
  };

  failedAssertions = map (x: x.message) (lib.filter (x: !x.assertion) config.assertions);
  baseSystemAssertWarn =
    if failedAssertions != [ ] then
      throw "\nFailed assertions:\n${lib.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else
      lib.showWarnings config.warnings baseSystem;
in
{
  options = {
    system.build = {
      toplevel = lib.mkOption {
        type = types.package;
        readOnly = true;
      };
    };
  };

  config = {
    system.build.toplevel = baseSystemAssertWarn;
  };
}
