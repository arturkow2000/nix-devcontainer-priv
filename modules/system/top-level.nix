{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  systemBuilder =
    ''
      mkdir -p $out/{tmp,opt,var}
    ''
    # XXX: workaround. When security wrappers are enabled put files in /run/wrappers/bin.
    # Those files have attached permissions (setuid, setgid, etc.) which we pass to nix2container
    # through perms attributes, but this causes conflicts in nix2container.
    # For now just let security wrapper package create /run.
    + lib.optionalString (!config.security.enableWrappers) ''
      mkdir -p $out/run
    ''
    + ''
      mkdir $out/usr
      while IFS= read -rd "" f; do
        ln -s "${config.system.path}/$f" $out/usr/
      done < <(ls -A --zero "${config.system.path}" | sed --zero '/^etc$/d')

      # devcontainer CLI (and vscode) expects at least /bin/sh available.
      ln -s /usr/{bin,sbin} $out/

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
    environment.variables = {
      PATH = [
        "/usr/sbin"
        "/usr/bin"
      ];
    };
  };
}
