# ck: because "duck" was too long to type...
#
#   ck [query]             jump to a local clone, fuzzy picking if several match
#   ck get <repo>          clone, or jump to the existing clone
#   ck list [query]        list local clones
#   ck rm <repo>           remove a local clone
#   ck new <repo>          start a new repo in the layout
#   ck fork                fork origin on GitHub, add it as `contrib`
#   ck tidy                move repos and fix remotes to match the layout
#   ck config              show the settings in use
#
# <repo> is a clone URL, `host/owner/repo`, `owner/repo` (on the default host),
# or a bare `repo`, which is looked up among local clones first, then under the
# default owner. Settings live in $XDG_CONFIG_HOME/ck/config.nuon; see config.nu.

use config.nu *
use lib.nu *
use tidy.nu *

# Jump to a local clone. Several matches open a fuzzy picker, and no query
# picks from all clones. Outside an interactive shell, print its path instead.
export def --env main [
    query?: string@complete-clones
] {
    let path = (jump (matching $query) $query)
    if not $nu.is-interactive { $path }
}

# Clone a repo into the layout, or jump to the existing clone (outside an
# interactive shell, print its path).
export def --env "ck get" [
    repo: string@complete-clones  # URL, host/owner/repo, owner/repo or repo.
    --update (-u)                 # Fetch if the clone already exists.
    --depth (-d): int             # Shallow clone with this much history.
    --branch (-b): string         # Only fetch this branch.
    --ssh (-p)                    # Clone shorthands over SSH instead of HTTPS.
] {
    let repo = (resolve $repo $ssh)

    if ($repo.path | path exists) {
        if not ($repo.path | path join ".jj" | path exists) {
            error make {msg: $"($repo.path) exists but is not a jj repo"}
        }
        cd $repo.path
        if $update { ^jj git fetch }
        if not $nu.is-interactive { return $repo.path }
        return
    }

    print $"Cloning into ($repo.path)..."
    mkdir ($repo.path | path dirname)

    let flags = (
        [--colocate --color always]
        | append (if $depth != null { [--depth ($depth | into string)] } else { [] })
        | append (if $branch != null { [--branch $branch] } else { [] })
    )
    let clone = (do { ^jj git clone ...$flags $repo.url $repo.path } | complete)

    if ($clone.stdout | is-not-empty) { print --raw --no-newline $clone.stdout }
    if ($clone.stderr | is-not-empty) { print --stderr --raw --no-newline $clone.stderr }

    if $clone.exit_code != 0 {
        rm --recursive --force $repo.path
        prune-empty $repo.path
        error make {msg: $"jj git clone failed with exit code ($clone.exit_code): ($repo.url)"}
    }

    cd $repo.path
    # The identity is picked by path, so this shows which one the clone landed under.
    print $"Identity: (^jj config get user.name) <(^jj config get user.email)>"
}

# List local clones whose name contains QUERY.
export def "ck list" [
    query?: string
    --exact (-e)      # QUERY must be the repo, owner/repo, or the full name.
    --full-path (-p)  # Only print full paths.
] {
    let found = if $exact { matching --exact $query } else { matching $query }
    if $full_path { $found | get path } else { $found }
}

# Remove a local clone.
export def --env "ck rm" [
    repo: string@complete-clones
    --dry-run (-n)  # Only print what would be removed.
    --yes (-y)      # Do not ask.
] {
    let found = (matching --exact $repo)

    if ($found | length) != 1 {
        let names = ($found | get name | str join ", ")
        error make {msg: $"($repo) matches ($found | length) clones: ($names)"}
    }

    let path = $found.0.path

    if $dry_run {
        return $path
    }

    let log = (
        do {
            (^jj log -R $path --no-graph
                -r '~::remote_bookmarks() ~ empty() ~ root()'
                -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"')
        } | complete
    )

    if $log.exit_code != 0 {
        error make {msg: $"Could not check ($path) for local changes, not removing it:\n($log.stderr)"}
    }

    if not (sole-workspace $path) {
        error make {msg: $"($path) shares its repo with other workspaces, remove it by hand"}
    }

    # jj warns here about files it would not snapshot, e.g. ones over its size limit.
    if ($log.stderr | is-not-empty) { print --stderr --raw --no-newline $log.stderr }
    let local_only = ($log.stdout | lines)

    if ($local_only | is-not-empty) {
        print $"(ansi yellow)Changes no remote has:(ansi reset)"
        $local_only | each { print $"  ($in)" }
    }

    if not $yes and (input $"Remove ($path)? [y/N] " | str lowercase) != "y" {
        return
    }

    # Step out of the clone, or out of a parent that pruning may remove.
    let pwd = $env.PWD
    if $pwd == $path or ($pwd | str starts-with $"($path)/") or ($path | str starts-with $"($pwd)/") and $pwd not-in (all-roots) {
        cd (base-dir)
    }
    ^rm --recursive --force $path
    prune-empty $path
}

# Start a new repo in the layout, with origin already set, and jump to it.
export def --env "ck new" [
    repo: string                # host/owner/repo, owner/repo or repo.
    --template (-t): string     # Flake template for `nix flake init -t`.
    --https                     # Set origin over HTTPS instead of SSH.
] {
    let repo = (resolve $repo (not $https))

    if ($repo.url? == null) or ($repo.path | path exists) {
        error make {msg: $"($repo.path) already exists"}
    }

    mkdir $repo.path
    cd $repo.path
    ^jj git init --colocate
    ^jj git remote add origin $repo.url

    if $template != null {
        ^nix flake init --template $template
    }
}

# Fork the current repo's origin on GitHub to your account and add the fork as
# the `contrib` remote.
export def "ck fork" [] {
    let origin = (^jj git remote list | lines | parse "{name} {url}" | where name == origin | get --optional url.0)

    if $origin == null {
        error make {msg: "No origin remote in this repo"}
    }

    let repo = (parts $origin)

    if ($repo.error? != null) {
        error make {msg: $repo.error}
    }

    if $repo.parts.0 != "github.com" {
        error make {msg: $"ck fork only supports github.com, origin is on ($repo.parts.0)"}
    }

    let upstream = ($repo.parts | skip 1 | str join "/")
    let login = (^gh api user --jq .login | str trim)
    let fork = $"($login)/($repo.parts | last)"

    # Succeeds without changes if the fork already exists.
    ^gh repo fork $upstream --clone=false

    # gh renames the fork if the name is taken by something else, so we need to make sure
    # the repo we are about to push to really is a fork of origin.
    let parent = (
        ^gh repo view $fork --json parent --jq '.parent | "\(.owner.login)/\(.name)"'
        | str trim
        | str lowercase
    )

    if $parent != $upstream {
        error make {msg: $"($fork) is not a fork of ($upstream)"}
    }

    let url = $"git@github.com:($fork).git"
    let has_contrib = (^jj git remote list | lines | parse "{name} {url}" | any {|r| $r.name == contrib })

    if $has_contrib {
        ^jj git remote set-url contrib $url
    } else {
        ^jj git remote add contrib $url
    }

    ^jj git fetch --remote contrib
    print $"(ansi green)contrib(ansi reset) → ($url)"
}

# Tidy every clone into the layout. The project is `origin`, your fork of it
# `contrib`; stale SSH host aliases are rewritten, duplicate remotes dropped,
# and repos moved to where `ck get` would clone their origin. Shows the plan
# unless --apply is given.
export def --env "ck tidy" [
    --apply                   # Carry out the plan.
    --me: string              # Comma-separated owners whose repos count as your forks.
] {
    let me = if $me == null { (settings).me } else { $me | split row "," | str trim | compact --empty }
    let base = (base-dir)
    let plans = (
        clones
        | par-each {|c| tidy-plan $c.path $me }
        | where ($it.steps | is-not-empty) or $it.target != null or $it.issue != null
        | sort-by root
    )
    # Clones that would land in the same place are left for you to sort out.
    let taken = ($plans | where target != null | get target | uniq --repeated)
    let plans = ($plans | each {|p|
        if $p.target in $taken { $p | merge {target: null, issue: $"another clone also moves to ($p.target)"} } else { $p }
    })

    if not $apply {
        return (
            $plans | each {|p|
                {
                    repo: (show $p.root)
                    remotes: ($p.steps | each { str join " " } | str join "\n")
                    move: (if $p.target != null { show $p.target })
                    issue: $p.issue
                }
            }
        )
    }

    for p in ($plans | where issue == null) {
        for step in $p.steps {
            ^jj git remote ...$step -R $p.root
        }
        if $p.target != null {
            if ($p.target | path exists) {
                print $"(ansi yellow)skipped move(ansi reset) (show $p.root): ($p.target) already exists"
                continue
            }
            mkdir ($p.target | path dirname)
            let pwd = $env.PWD
            let inside = $pwd == $p.root or ($pwd | str starts-with $"($p.root)/")
            # Pruning may remove a parent we are in.
            if not $inside and ($p.root | str starts-with $"($pwd)/") { cd $base }
            mv $p.root $p.target
            if $inside { cd ($p.target | path join ($pwd | path relative-to $p.root)) }
            prune-empty $p.root
        }
        print $"(ansi green)tidied(ansi reset) (show $p.root)"
    }

    for p in ($plans | where issue != null) {
        print $"(ansi yellow)skipped(ansi reset) (show $p.root): ($p.issue)"
    }
}

# Show the settings in use and the file they are read from.
export def "ck config" [] {
    settings | insert file (config-path)
}
