# Planning for `ck tidy`.

use config.nu *
use lib.nu [parts target sole-workspace]

export def dealias [url: string] {
    (settings).host_aliases
    | transpose alias host
    | reduce --fold $url {|a, url|
        $url | str replace --regex ('^((?:ssh://)?(?:[^@/:]+@)?)' + $a.alias + '([:/])') ('${1}' + $a.host + '${2}')
    }
}

export def tidy-plan [root: path, me: list<string>] {
    let me = ($me | str lowercase)
    let role_remotes = ((settings).role_remotes | append $me | uniq)
    let remotes = (
        ^jj git remote list --ignore-working-copy -R $root e> /dev/null
        | lines
        | parse "{name} {url}"
        | each {|r|
            let url = (dealias $r.url)
            let p = (parts $url).parts?
            $r | merge {
                new_url: $url
                key: ($p | default [$url] | str join "/")
                mine: ($p != null and (($p | last 2 | first) in $me))
            }
        }
    )
    # Prefer remotes that already carry the name they will end up with.
    let roles = ($remotes | where name in $role_remotes | sort-by {|r| $r.name not-in [origin contrib] })
    let upstreams = ($roles | where mine == false | uniq-by key)
    let forks = ($roles | where mine | uniq-by key)

    let chosen = if ($upstreams | length) > 1 {
        {issue: $"several upstreams: ($upstreams.name | str join ', ')"}
    } else if ($forks | length) > 1 {
        {issue: $"several forks: ($forks.name | str join ', ')"}
    } else if ($upstreams | is-not-empty) {
        {origin: $upstreams.0, contrib: $forks.0?}
    } else if ($forks | is-not-empty) {
        {origin: $forks.0}
    } else {
        {issue: "no origin remote"}
    }

    if ($chosen.issue? != null) {
        return {root: $root, steps: [], target: null, issue: $chosen.issue}
    }

    let keep = ([$chosen.origin $chosen.contrib?] | compact | insert final {|r| if $r.key == $chosen.origin.key { "origin" } else { "contrib" } })
    let renames = ($keep | where name != $it.final)
    # Swapping names (upstream/origin -> origin/contrib) needs a detour.
    let swap = ($renames | any {|r| $r.final in $keep.name })
    let rename_steps = if $swap {
        ($renames | each {|r| [rename $r.name $"ck-($r.final)"] })
        | append ($renames | each {|r| [rename $"ck-($r.final)" $r.final] })
    } else {
        $renames | each {|r| [rename $r.name $r.final] }
    }

    let steps = (
        ($roles | where name not-in $keep.name | each {|r| [remove $r.name] })
        | append $rename_steps
        | append ($keep | where url != $it.new_url | each {|r| [set-url $r.final $r.new_url] })
        | append ($remotes | where name not-in $role_remotes and url != $it.new_url | each {|r| [set-url $r.name $r.new_url] })
    )

    let target = (target $chosen.origin.new_url).path?
    let issue = if $target == null {
        "origin does not name a forge repo"
    } else if ($target | str starts-with $"($root)/") {
        $"would move into itself: ($target)"
    } else if $target != $root and ($target | path exists) {
        $"($target) already exists"
    } else if $target != $root and not (sole-workspace $root) {
        "has several workspaces, move it by hand"
    } else if $swap and ($renames | any {|r| $"ck-($r.final)" in $remotes.name }) {
        "a ck-origin or ck-contrib remote is in the way"
    }

    {root: $root, steps: $steps, target: (if $target != $root and $issue == null { $target }), issue: $issue}
}
