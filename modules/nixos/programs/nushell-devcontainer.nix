# Various tweaks for nushell.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabledOption =
    x:
    lib.mkEnableOption x
    // {
      default = true;
      example = false;
    };
  nushellConfig = pkgs.writeTextDir "share/nushell/vendor/autoload/50-nu-config.nu" (
    (
      ''
        use std/config *
      ''
      + lib.concatStringsSep "\n" (
        lib.mapAttrsToListRecursive (
          path: value:
          let
            path' = lib.concatStringsSep "." path;
            value' =
              if builtins.typeOf value == "string" then
                ''"${lib.escapeShellArg value}"''
              else if builtins.typeOf value == "bool" then
                if value then "true" else "false"
              else if builtins.typeOf value == "int" || builtins.typeOf value == "float" then
                toString value
              else
                throw "Unsupported value type ${builtins.typeOf value}";
          in
          "$env.config.${path'} = ${value'}"
        ) config.programs.nushell.settings
      )
    )
  );
  # pre-generated using `starship init nu`
  # currently nushell doesn't allow sourcing code without first saving it somewhere on the disk
  # e.g. `starship init nu | source` won't work.
  # We are not doing it at build time because config.starship.package is for target architecture and we can't
  # obtain native binary from that.
  nushellStarship = pkgs.writeTextDir "share/nushell/vendor/autoload/50-starship.nu" ''
    # this file is both a valid
    # - overlay which can be loaded with `overlay use starship.nu`
    # - module which can be used with `use starship.nu`
    # - script which can be used with `source starship.nu`
    export-env { $env.STARSHIP_SHELL = "nu"; load-env {
        STARSHIP_SESSION_KEY: (random chars -l 16)
        PROMPT_MULTILINE_INDICATOR: (
            ^/usr/bin/starship prompt --continuation
        )

        # Does not play well with default character module.
        # TODO: Also Use starship vi mode indicators?
        PROMPT_INDICATOR: ""

        PROMPT_COMMAND: {||
            (
                # The initial value of `$env.CMD_DURATION_MS` is always `0823`, which is an official setting.
                # See https://github.com/nushell/nushell/discussions/6402#discussioncomment-3466687.
                let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
                ^/usr/bin/starship prompt
                    --cmd-duration $cmd_duration
                    $"--status=($env.LAST_EXIT_CODE)"
                    --terminal-width (term size).columns
                    ...(
                        if (which "job list" | where type == built-in | is-not-empty) {
                            ["--jobs", (job list | length)]
                        } else {
                            []
                        }
                    )
            )
        }

        config: ($env.config? | default {} | merge {
            render_right_prompt_on_last_line: true
        })

        PROMPT_COMMAND_RIGHT: {||
            (
                # The initial value of `$env.CMD_DURATION_MS` is always `0823`, which is an official setting.
                # See https://github.com/nushell/nushell/discussions/6402#discussioncomment-3466687.
                let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
                ^/usr/bin/starship prompt
                    --right
                    --cmd-duration $cmd_duration
                    $"--status=($env.LAST_EXIT_CODE)"
                    --terminal-width (term size).columns
                    ...(
                        if (which "job list" | where type == built-in | is-not-empty) {
                            ["--jobs", (job list | length)]
                        } else {
                            []
                        }
                    )
            )
        }
    }}
  '';
  # Based on https://www.nushell.sh/cookbook/direnv.html
  nushellDirenv = pkgs.writeTextDir "share/nushell/vendor/autoload/50-direnv.nu" ''
    use std/config *
    $env.config.hooks.env_change.PWD = $env.config.hooks.env_change.PWD? | default []
    $env.config.hooks.env_change.PWD ++= [{||
      direnv export json | from json | default {} | update cells --columns [ PATH ] {
        do (env-conversions).path.from_string $in
      } | load-env
    }]
  '';
in
{
  options = {
    programs.nushell = {
      settings = lib.mkOption {
        default = { };
        type = lib.types.submodule {
          freeformType = lib.types.anything;
        };
      };
    };
    programs.direnv = {
      enableNushellIntegration = enabledOption ''
        Nushell integration
      '';
    };
  };
  config = lib.mkMerge [
    {
      programs.nushell.settings = lib.mapAttrsRecursive (_: lib.mkDefault) {
        # Disable default greeting banner.
        show_banner = false;
        history.file_format = "sqlite";
        history.isolation = true;
        # Allows pasting of multiple lines without execution.
        bracketed_paste = true;
        table.mode = "compact";
        filesize = {
          unit = "binary";
          show_unit = true;
          precision = 2;
        };
        shell_integration = {
          osc2 = true;
          osc8 = false;
          osc133 = true;
          osc633 = true;
        };
        completions = {
          algorithm = "fuzzy";
          case_sensitive = false;
        };
      };
    }
    {
      programs.nushell.autoloads = [ nushellConfig ];
    }
    (lib.mkIf config.programs.starship.enable {
      programs.nushell.autoloads = [ nushellStarship ];
    })
    (lib.mkIf (config.programs.direnv.enable && config.programs.direnv.enableNushellIntegration) {
      programs.nushell.autoloads = [ nushellDirenv ];
    })
  ];
}
