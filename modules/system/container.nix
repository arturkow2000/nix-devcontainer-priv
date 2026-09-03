{ lib, config, ... }:
let
  inherit (lib) types;
  fsAttrs =
    { ... }:
    {
      options = {
        package = lib.mkOption {
          type = types.package;
          description = "Package to apply permissions to";
        };

        file = lib.mkOption {
          type = types.path;
          description = "Path to the file, relative to package directory";
        };

        uid = lib.mkOption {
          type = types.int;
          description = "UID of file owner";
        };

        gid = lib.mkOption {
          type = types.int;
          description = "GID of file owner";
        };

        mode = lib.mkOption {
          type = types.str;
          # TODO: validate
          description = "File mode in octal form";
          example = "0755";
        };
      };
    };
in
{
  options = {
    system.nixos = {
      containerName = lib.mkOption {
        type = with types; nullOr str;
        default = null;
      };

      containerMaxLayers = lib.mkOption {
        type = lib.types.int;
        # There used to be much lower limit in Docker, but now seems to work properly
        # with latest version.
        default = 256;
      };

      nixStoreUid = lib.mkOption {
        type = lib.types.int;
        default = config.ids.uids.root;
      };

      nixStoreGid = lib.mkOption {
        type = lib.types.int;
        default = config.ids.uids.root;
      };
    };

    system.build = {
      perms = lib.mkOption {
        type = with types; listOf (submodule fsAttrs);
        default = { };
        description = ''
          A dictionary of files/directories and theirs fs attributes (ownership, permissions)
          to be set in the container image.
        '';
      };
    };
  };
}
