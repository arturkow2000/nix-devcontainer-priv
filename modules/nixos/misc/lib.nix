# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
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
