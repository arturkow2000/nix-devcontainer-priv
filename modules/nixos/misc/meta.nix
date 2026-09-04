# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{ lib, ... }:
let
  docFile = lib.types.path // {
    # Returns tuples of
    #   { file = "module location"; value = <path/to/doc.xml>; }
    merge = loc: defs: defs;
  };
in

{
  imports = [ ../../../modules/generic/meta-maintainers.nix ];

  options = {
    meta = {

      doc = lib.mkOption {
        type = docFile;
        internal = true;
        example = "./meta.chapter.md";
        description = ''
          Documentation prologue for the set of options of each module.  This
          option should be defined at most once per module.
        '';
      };

      buildDocsInSandbox = lib.mkOption {
        type = lib.types.bool // {
          merge = loc: defs: defs;
        };
        internal = true;
        default = true;
        description = ''
          Whether to include this module in the split options doc build.
          Disable if the module references `config`, `pkgs` or other module
          arguments that cannot be evaluated as constants.

          This option should be defined at most once per module.
        '';
      };

    };
  };

  meta.maintainers = with lib.maintainers; [
    pierron
    roberth
  ];
}
