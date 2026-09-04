# Vendored from nixpkgs rev ff8d74d0097bbdcf430e5e866c0c1d795f138ab4
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{ lib, ... }:

{
  options = {
    lib = lib.mkOption {
      default = { };

      type = lib.types.attrsOf lib.types.attrs;

      description = ''
        This option allows modules to define helper functions, constants, etc.
      '';
    };
  };
}
