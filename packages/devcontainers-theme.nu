def __git-config [key: string] {
    git config --get $key | ignore --stderr | str trim
}

def __git-branch [] {
    let branch = (
        git --no-optional-locks symbolic-ref --short HEAD
            | ignore --stderr | str trim
    )

    if ($branch | is-empty) {
        git --no-optional-locks rev-parse --short HEAD | ignore --stderr | str trim
    } else {
        $branch
    }
}

def __git-is-dirty [] {
    let result = (
        git --no-optional-locks ls-files
            --error-unmatch -m --directory
            --no-empty-directory -o --exclude-standard ":/*"
            e>| complete
    )

    $result.exit_code == 0
}

def __git-prompt [] {
    let hide_devcontainers = (__git-config "devcontainers-theme.hide-status") == "1"
    let hide_codespaces = (__git-config "codespaces-theme.hide-status") == "1"

    if $hide_devcontainers or $hide_codespaces {
        return ""
    }

    let branch = (__git-branch)
    if ($branch | is-empty) {
        return ""
    }

    let dirty = if (__git-config "devcontainers-theme.show-dirty") == "1" {
        if (__git-is-dirty) {
            $" (ansi yellow)✗"
        } else {
            ""
        }
    } else {
        ""
    }

    $"(ansi {fg: cyan, attr: [bold]})\((ansi red)($branch)($dirty)(ansi cyan)\)(ansi reset) "
}

$env.PROMPT_INDICATOR = $"(ansi white)$ (ansi reset)"
$env.PROMPT_COMMAND = {||
    let exit_code = $env.LAST_EXIT_CODE
    let username = if ($env.GITHUB_USER? | is-not-empty) {
        $"@($env.GITHUB_USER)"
    } else {
        $env.USER? | default (whoami)
    }

    let arrow = if $exit_code == 0 {
        $"(ansi green)($username) (ansi reset)➜ "
    } else {
        $"(ansi green)($username) (ansi red)➜ "
    }

    let cwd = try {
        let cwd = pwd | path relative-to $nu.home-dir
        if ($cwd | is-empty) {
            char home
        } else {
            $"(char home)(char path_sep)($cwd)"
        }
    } catch { pwd }

    $"($arrow)(ansi blue)($cwd)(ansi reset) " + (__git-prompt)
}
