{ pkgs, ... }:
pkgs.writeTextFile {
  name = "zsh-theme-devcontainers";
  text = builtins.readFile ./devcontainers.zsh-theme;
  destination = "/share/zsh/themes/devcontainers.zsh-theme";
}
