# Based on nixpkgs 24a69cdc73f76df4dde9edabcda6737f55b66627.
# Changes:
#   - remove environment.profiles
#   - remove environment.profileRelativeEnvVars
#   - remove environment.homeBinInPath (PAM bypass)
#   - remove environment.localBinInPath (PAM bypass)
{
  config,
  lib,
  utils,
  pkgs,
  ...
}:
let
  cfg = config.environment;
in
{
  options = {
    environment.variables = lib.mkOption {
      default = { };
      example = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
      description = ''
        A set of environment variables used in the global environment.
        These variables will be set when starting container.

        The value of each variable can be either a string or a list of
        strings.  The latter is concatenated, interspersed with colon
        characters.

        Setting a variable to `null` does nothing. You can override a
        variable set by another module to `null` to unset it.
      '';
      type =
        with lib.types;
        attrsOf (
          nullOr (oneOf [
            (listOf (oneOf [
              int
              str
              path
            ]))
            int
            str
            path
          ])
        );
      apply =
        let
          toStr = v: if lib.isPath v then "${v}" else toString v;
        in
        attrs:
        lib.mapAttrs (n: v: if lib.isList v then lib.concatMapStringsSep ":" toStr v else toStr v) (
          lib.filterAttrs (n: v: v != null) attrs
        );
    };

    # !!! isn't there a better way?
    environment.extraInit = lib.mkOption {
      default = "";
      description = ''
        Shell script code called during global environment initialisation
        after all variables and profileVariables have been set.
        This code is assumed to be shell-independent, which means you should
        stick to pure sh without sh word split.
      '';
      type = lib.types.lines;
    };

    environment.shellInit = lib.mkOption {
      default = "";
      description = ''
        Shell script code called during shell initialisation.
        This code is assumed to be shell-independent, which means you should
        stick to pure sh without sh word split.
      '';
      type = lib.types.lines;
    };

    environment.loginShellInit = lib.mkOption {
      default = "";
      description = ''
        Shell script code called during login shell initialisation.
        This code is assumed to be shell-independent, which means you should
        stick to pure sh without sh word split.
      '';
      type = lib.types.lines;
    };

    environment.interactiveShellInit = lib.mkOption {
      default = "";
      description = ''
        Shell script code called during interactive shell initialisation.
        This code is assumed to be shell-independent, which means you should
        stick to pure sh without sh word split.
      '';
      type = lib.types.lines;
    };

    environment.shellAliases = lib.mkOption {
      example = {
        l = null;
        ll = "ls -l";
      };
      description = ''
        An attribute set that maps aliases (the top level attribute names in
        this option) to command strings or directly to build outputs. The
        aliases are added to all users' shells.
        Aliases mapped to `null` are ignored.
      '';
      type = with lib.types; attrsOf (nullOr (either str path));
    };

    environment.binsh = lib.mkOption {
      default = "${config.system.build.binsh}/bin/sh";
      defaultText = lib.literalExpression ''"''${config.system.build.binsh}/bin/sh"'';
      example = lib.literalExpression ''"''${pkgs.dash}/bin/dash"'';
      type = lib.types.path;
      visible = false;
      description = ''
        The shell executable that is linked system-wide to
        `/bin/sh`. Please note that NixOS assumes all
        over the place that shell to be Bash, so override the default
        setting only if you know exactly what you're doing.
      '';
    };

    environment.shells = lib.mkOption {
      default = [ ];
      example = lib.literalExpression "[ pkgs.bashInteractive pkgs.zsh ]";
      description = ''
        A list of permissible login shells for user accounts.
        No need to mention `/bin/sh`
        here, it is placed into this list implicitly.
      '';
      type = lib.types.listOf (lib.types.either lib.types.shellPackage lib.types.path);
    };
  };

  config = {
    system.build.binsh = pkgs.bashInteractive;

    environment.shellAliases = lib.mapAttrs (name: lib.mkDefault) {
      ls = "ls --color=tty";
      ll = "ls -l";
      l = "ls -alh";
    };

    environment.etc.shells.text = ''
      ${lib.concatStringsSep "\n" (map utils.toShellPath cfg.shells)}
      /bin/sh
    '';

    system.build.setEnvironment = pkgs.writeText "set-environment" ''
      # DO NOT EDIT -- this file has been generated automatically.

      # Prevent this file from being sourced by child shells.
      export __NIXOS_SET_ENVIRONMENT_DONE=1

      ${cfg.extraInit}
    '';
  };
}
