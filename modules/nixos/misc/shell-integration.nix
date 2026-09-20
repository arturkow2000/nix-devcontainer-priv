{ pkgs, ... }:
let
  # Set default git editor if not already set.
  # Logic copied from Microsoft's base container.
  posixShellInit = ''
    if [ -z "$(git config --get core.editor)" ] && [ -z "''${GIT_EDITOR-}" ]; then
      if  [ "''${TERM_PROGRAM-}" = "vscode" ]; then
          if [[ -n "$(command -v code-insiders)" && -z "$(command -v code)" ]]; then 
              export GIT_EDITOR="code-insiders --wait"
          else
              export GIT_EDITOR="code --wait"
          fi
      fi
    fi
  '';
  fishInit = ''
    if test -z "$(git config --get core.editor)" && test -z "$GIT_EDITOR"
      if test "$TERM_PROGRAM" = vscode
          if command -q code-insiders; and not command -q code
              set -gx GIT_EDITOR "code-insiders --wait"
          else
              set -gx GIT_EDITOR "code --wait"
          end
      end
    end
  '';
  nushellInit = pkgs.writeTextDir "share/nushell/vendor/autoload/50-vscode-integration.nu" ''
    if (git config --get core.editor | is-empty) and ($env.GIT_EDITOR? | is-empty) {
      if ($env.TERM_PROGRAM? == "vscode") {
        let insiders = which code-insiders | is-not-empty
        let stable = which code | is-not-empty
        if $insiders and not $stable {
            $env.GIT_EDITOR = "code-insiders --wait"
        } else {
            $env.GIT_EDITOR = "code --wait"
        }
      }
    }
  '';
in
{
  programs.bash.interactiveShellInit = posixShellInit;
  programs.zsh.interactiveShellInit = posixShellInit;
  programs.fish.interactiveShellInit = fishInit;
  programs.nushell.autoloads = [ nushellInit ];
}
