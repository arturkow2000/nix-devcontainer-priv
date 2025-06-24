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
  inherit (flake.inputs.nix2container.packages.${flakeArchBuild}) nix2container;
  flakeArchBuild = parsedArchToFlake pkgs.stdenv.buildPlatform.parsed;
  baseOsLayer = nix2container.buildLayer {
    deps = config.build.requiredPackages ++ config.environment.defaultPackages;
    metadata.created_by = "nix2container base layer";
  };
  getAllDeps =
    packages:
    let
      raw = pkgs.writeClosure packages;
    in
    lib.filter (x: (lib.stringLength x) > 0) (lib.splitString "\n" (builtins.readFile raw));
  allDepsInLayers = getAllDeps (
    lib.flatten (
      lib.catAttrs "deps" (
        config.system.build.layers
        ++ [
          catchallLayer
          toplevelLayer
        ]
      )
    )
  );
  allDeps = getAllDeps config.system.build.toplevel;
  strayDeps = lib.subtractLists allDepsInLayers allDeps;

  catchallLayer = nix2container.buildLayer {
    deps = map (x: lib.warn "stray dep: ${builtins.toString x}" x) strayDeps;
    layers = config.system.build.layers;
    metadata.created_by = "nix2container catchall layer";
  };
  toplevelLayer = nix2container.buildLayer {
    layers = config.system.build.layers ++ [ catchallLayer ];
    deps = [
      config.system.path
      config.system.build.etc
    ];
    copyToRoot = config.system.build.toplevel;
    metadata.created_by = "nix2container toplevel layer";
  };
in
{
  options = {
    system.build.nix2container = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
    system.build.layers = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
    };
  };

  config = {
    system.build.layers = [
      baseOsLayer
    ];

    system.build.nix2container = nix2container.buildImage {
      name =
        if (config.system.nixos.containerName != null) then
          config.system.nixos.containerName
        else
          "nixos-${config.system.nixos.label}";
      tag = "latest";
      config = {
        cmd = [
          (utils.toShellPath config.users.users.root.shell)
          "--login"
        ];
      };
      layers = config.system.build.layers ++ [
        toplevelLayer
      ];
    };
  };
}
