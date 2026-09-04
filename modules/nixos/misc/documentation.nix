{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    cleanSourceFilter
    concatMapStringsSep
    evalModules
    filter
    functionArgs
    hasSuffix
    isAttrs
    isDerivation
    isFunction
    isPath
    literalExpression
    mapAttrs
    mkIf
    mkMerge
    mkOption
    mkRemovedOptionModule
    mkRenamedOptionModule
    optional
    optionalAttrs
    optionals
    partition
    removePrefix
    types
    warn
    ;
  cfg = config.documentation;
in
{
  options = {
    documentation = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install documentation of packages from
          {option}`environment.systemPackages` into the generated system path.

          See "Multiple-output packages" chapter in the nixpkgs manual for more info.
        '';
        # which is at ../../../doc/multiple-output.chapter.md
      };

      man.enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install manual pages.
          This also includes `man` outputs.
        '';
      };

      man.cache.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to generate the manual page index caches.
          This allows searching for a page or
          keyword using utilities like {manpage}`apropos(1)`
          and the `-k` option of
          {manpage}`man(1)`.
        '';
      };

      info.enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install info pages and the {command}`info` command.
          This also includes "info" outputs.
        '';
      };

      doc.enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to install documentation distributed in packages' `/share/doc`.
          Usually plain text and/or HTML.
          This also includes "doc" outputs.
        '';
      };

      dev.enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to install documentation targeted at developers.
          * This includes man pages targeted at developers if {option}`documentation.man.enable` is
            set (this also includes "devman" outputs).
          * This includes info pages targeted at developers if {option}`documentation.info.enable`
            is set (this also includes "devinfo" outputs).
          * This includes other pages targeted at developers if {option}`documentation.doc.enable`
            is set (this also includes "devdoc" outputs).
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.man.man-db.enable && (cfg.man.mandoc.enable or false));
          message = ''
            man-db and mandoc can't be used as the default man page viewer at the same time!
          '';
        }
      ];
    }
    # The actual implementation for this lives in man-db.nix or mandoc.nix,
    # depending on which backend is active.
    (mkIf cfg.man.enable {
      environment.pathsToLink = [ "/share/man" ];
      environment.extraOutputsToInstall = [ "man" ] ++ optional cfg.dev.enable "devman";
    })

    (mkIf cfg.info.enable {
      environment.systemPackages = [ pkgs.texinfoInteractive ];
      environment.pathsToLink = [ "/share/info" ];
      environment.extraOutputsToInstall = [ "info" ] ++ optional cfg.dev.enable "devinfo";
      environment.extraSetup = ''
        if [ -w $out/share/info ]; then
          shopt -s nullglob
          for i in $out/share/info/*.info $out/share/info/*.info.gz; do
              ${pkgs.buildPackages.texinfo}/bin/install-info $i $out/share/info/dir
          done
        fi
      '';
    })

    (mkIf cfg.doc.enable {
      environment.pathsToLink = [
        "/share/doc"

        # Legacy paths used by gtk-doc & adjacent tools.
        "/share/gtk-doc"
        "/share/devhelp"
      ];
      environment.extraOutputsToInstall = [ "doc" ] ++ optional cfg.dev.enable "devdoc";
    })
  ]);
}
