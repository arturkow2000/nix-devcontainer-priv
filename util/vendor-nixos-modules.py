# Utility for vendoring NixOS modules.
# We do this so that users of nix-devcontainer may freely update nixpkgs without risking breakage,
# as many NixOS modules depend either directly or indirectly on SystemD and other features that either
# absolutely will not work, or that are probablematic and require some tradeoffs (e.g. running with --privileged).

from argparse import ArgumentParser
from pathlib import Path
from typing import List, Callable
import subprocess
import shlex
import sys
import json
import shutil
import os


class WithProcessors:
    def __init__(self, file: str, processors: List[Callable[[str], str]]):
        self.file = file
        self.processors = processors


def fixup_nixpkgs_import(f: str) -> str:
    # nixpkgs.nix uses relative path to import nixpkgs root, but this becomes invalid
    # when module file is moved elsewhere.
    return f.replace("pkgs,\n", "pkgs,\n  __nixpkgs_path,\n").replace(
        "import ../../..", "import __nixpkgs_path"
    )


files_to_vendor = [
    "config/nix-flakes.nix",
    "config/nix-remote-build.nix",
    "config/nix.nix",
    "config/nsswitch.nix",
    "config/unix-odbc-drivers.nix",
    "misc/assertions.nix",
    "misc/ids.nix",
    "misc/label.nix",
    "misc/lib.nix",
    "misc/man-db.nix",
    "misc/meta.nix",
    WithProcessors("misc/nixpkgs.nix", [fixup_nixpkgs_import]),
    "misc/nixpkgs-flake.nix",
    "misc/passthru.nix",
    "misc/version.nix",
    "system/build.nix",
    "programs/bash-my-aws.nix",
    "programs/bash/bash.nix",
    "programs/bash/bash-completion.nix",
    "programs/bash/ls-colors.nix",
    "programs/bash/blesh.nix",
    "programs/bash/undistract-me.nix",
    "programs/bash/inputrc",
    "programs/bat.nix",
    "programs/command-not-found/command-not-found.nix",
    "programs/direnv.nix",
    "programs/fish.nix",
    "programs/fzf.nix",
    "programs/git-worktree-switcher.nix",
    "programs/git.nix",
    "programs/htop.nix",
    "programs/lazygit.nix",
    "programs/less.nix",
    "programs/nano.nix",
    "programs/neovim.nix",
    "programs/starship.nix",
    "programs/vim.nix",
    "programs/xonsh.nix",
    "programs/zsh/oh-my-zsh.nix",
    "programs/zsh/zsh-autoenv.nix",
    "programs/zsh/zsh-autosuggestions.nix",
    "programs/zsh/zsh-syntax-highlighting.nix",
    "security/ca.nix",
]


def main():
    parser = ArgumentParser()
    parser.add_argument(
        "root",
        help="Path to this project (nix-devcontainer) root directory (where flake.nix is).",
    )
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_absolute():
        root_str = f"./{root}"
    else:
        root_str = str(root)

    result = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            "--impure",
            "--expr",
            rf"""
let
    flake = builtins.getFlake (toString {shlex.quote(root_str)});
in
{{
    nixpkgs = {{
        inherit (flake.inputs.nixpkgs) rev;
        path = flake.inputs.nixpkgs.outPath;
    }};
}}
""",
        ],
        stdin=None,
        stderr=sys.stderr,
        stdout=subprocess.PIPE,
    )
    if result.returncode != 0:
        sys.exit(result.returncode)
    r = json.loads(result.stdout.decode())

    rev = r["nixpkgs"]["rev"]
    nixpkgs = Path(r["nixpkgs"]["path"])

    for file in files_to_vendor:
        if isinstance(file, WithProcessors):
            path_src = nixpkgs / "nixos" / "modules" / Path(file.file)
            path_dst = root / "modules" / Path(file.file)
            processors = file.processors
        else:
            path_src = nixpkgs / "nixos" / "modules" / Path(file)
            path_dst = root / "modules" / Path(file)
            processors = []
        os.makedirs(path_dst.parent, exist_ok=True)

        with open(path_src, "r") as i, open(path_dst, "w") as o:
            o.write(f"""# Vendored from nixpkgs rev {rev}
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
""")
            if len(processors) > 0:
                o.write("# Processed by:\n")
                for proc in processors:
                    o.write(f"#  - {proc.__name__}\n")

                contents = i.read()
                for proc in processors:
                    contents = proc(contents)

                o.write(contents)
            else:
                shutil.copyfileobj(i, o)

            o.flush()


if __name__ == "__main__":
    main()
