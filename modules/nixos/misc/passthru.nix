# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
# This module allows you to export something from configuration
# Use case: export kernel source expression for ease of configuring

{ lib, ... }:

{
  options = {
    passthru = lib.mkOption {
      visible = false;
      description = ''
        This attribute set will be exported as a system attribute.
        You can put whatever you want here.
      '';
    };
  };
}
