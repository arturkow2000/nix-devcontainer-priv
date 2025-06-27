{ pkgs, ... }:
pkgs.writeTextFile {
  name = "bash-theme-devcontainers";
  text = builtins.readFile ./devcontainers.bash-theme;
}
