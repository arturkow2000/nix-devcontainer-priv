# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {

    system.build = mkOption {
      default = { };
      description = ''
        Attribute set of derivations used to set up the system.
      '';
      type = types.submoduleWith {
        modules = [
          {
            freeformType = with types; lazyAttrsOf (uniq unspecified);
          }
        ];
      };
    };

  };
}
