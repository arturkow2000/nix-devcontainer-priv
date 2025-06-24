{
  config,
  lib,
  flake,
  parsedArchToFlake,
  utils,
  pkgs,
  ...
}:
let
  inherit (flake.inputs.nix-snapshotter.packages.${flakeArchBuild}) nix-snapshotter;
  flakeArchBuild = parsedArchToFlake pkgs.stdenv.buildPlatform.parsed;
in
{
  options = {
    system.build.nix-snapshotter = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  config = {
    system.build.nix-snapshotter = nix-snapshotter.buildImage {
      name =
        if (config.system.nixos.containerName != null) then
          config.system.nixos.containerName
        else
          "nixos-${config.system.nixos.label}";
      tag = "latest";
      copyToRoot = config.system.build.toplevel;
      config = {
        cmd = [
          (utils.toShellPath config.users.users.root.shell)
          "--login"
        ];
      };
    };
  };
}
