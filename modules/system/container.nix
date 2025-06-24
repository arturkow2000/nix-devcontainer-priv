{ lib, ... }:
let
  inherit (lib) types;
  fsAttrs =
    { ... }:
    {
      options = {
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
        type = with types; nullOr string;
        default = null;
      };
    };

    system.build = {
      perms = lib.mkOption {
        type = with types; attrsOf (submodule fsAttrs);
        default = { };
        description = ''
          A dictionary of files/directories and theirs fs attributes (ownership, permissions)
          to be set in the container image.
        '';
      };
    };
  };
}
