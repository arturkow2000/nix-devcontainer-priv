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
  getAllDeps =
    packages:
    let
      raw = pkgs.writeClosure packages;
    in
    lib.filter (x: (lib.stringLength x) > 0) (lib.splitString "\n" (builtins.readFile raw));
  allDeps = getAllDeps config.system.build.toplevel;
  ownedDeps = getAllDeps config.system.build.layers ++ toplevelLayerDeps;
  strayDeps = lib.subtractLists ownedDeps allDeps;

  # Split the image into layers to avoid having to update full few gigabytes
  # images on each even smallest change. nix2container provides maxLayers settings
  # however due to Docker's limitations this may not be efficient. Manually create
  # base layer for most common packages which are always present, do the same for
  # the "toplevel" layer which holds configuration. Everything else is subject
  # to maxLayers setting.
  baseOsLayer = nix2container.buildLayer {
    # FIXME: changing defaultPackages triggers rebuild of everything. Perhabs
    # move this into separate layer on top of base OS?
    deps = config.build.requiredPackages ++ config.environment.defaultPackages;
    metadata.created_by = "nix2container base layer";
  };

  # This layer catches any derivations which aren't explicitly assigned to any layer
  # which would otherwise go into toplevel layer.
  catchallLayer = nix2container.buildLayer {
    deps = strayDeps;
    layers = config.system.build.layers;
    metadata.created_by = "nix2container catchall layer";
  };

  # Derivations which always put into toplevel layer.
  toplevelLayerDeps =
    let
      etcFiles = lib.mapAttrsToList (n: v: v.source) config.environment.etc;
    in
    [
      config.system.path
      config.system.build.etc
    ]
    ++ etcFiles;
  toplevelLayer = nix2container.buildLayer {
    layers = config.system.build.layers ++ lib.optional (lib.length strayDeps > 0) catchallLayer;
    deps = toplevelLayerDeps;
    copyToRoot = [
      config.system.build.toplevel
      config.system.build.etc
    ];
    perms = map (
      {
        package,
        file,
        mode,
        uid,
        gid,
      }:
      {
        path = package;
        regex = "^${package}${file}$";
        inherit mode uid gid;
      }
    ) config.system.build.perms;
    # If config file is copied to /etc instead of symlinked remove the copy from /nix/store.
    # Removes duplicated content and also what's particularly important prevents files from
    # being world-readable (such as /etc/shadow) if permissions don't allow this - permissions
    # are applied to files in /etc not to /nix/store!
    ignore =
      let
        etc' = lib.filter (f: f.enable && f.mode != "symlink") (lib.attrValues config.environment.etc);
      in
      map (f: f.source) etc';
    metadata.created_by = "nix2container toplevel layer";
  };

  allLayers =
    config.system.build.layers
    ++ lib.optional (lib.length strayDeps > 0) catchallLayer
    ++ [ toplevelLayer ];
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
      layers = allLayers;
    };
  };
}
