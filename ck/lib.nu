# Paths, URLs and local clones.

use config.nu *

export def base-dir [] { (settings).base | path expand }

export def all-roots [] {
    [(base-dir)] | append ((settings).roots | get --optional root | default [] | each { path expand }) | uniq
}

# The forge and path of a clone URL, from URL-shaped remotes (https://...,
# ssh://..., git://...) or SCP-shaped ones ([user@]forge:path/to/repo.git).
export def parse-url [url: string] {
    let has_scheme = ($url | parse --regex '^[A-Za-z][A-Za-z0-9+.-]*://.*$' | is-not-empty)
    let scp = if $has_scheme { [] } else {
        $url | parse --regex '^(?:(?:[^@/:]+)@)?(?P<host>[^/:]+):(?P<path>.+)$'
    }

    if ($scp | is-not-empty) {
        return {forge: ($scp.0.host | str lowercase), path: $scp.0.path}
    }

    let parsed = try { $url | url parse } catch { null }

    if ($parsed != null) and ($parsed.host | is-not-empty) {
        let forge = if ($parsed.port | is-empty) { $parsed.host } else { $"($parsed.host):($parsed.port)" }
        return {forge: ($forge | str lowercase), path: $parsed.path}
    }

    null
}

export def is-url [spec: string] {
    ($spec | str contains "://") or ($spec | parse --regex '^(?:[^@/:]+@)?[^/:]+:.+$' | is-not-empty)
}

# The [forge group... owner repo] parts of a clone URL, lowercased, or an error.
export def parts [url: string] {
    let remote = (parse-url $url)

    if $remote == null {
        return {error: $"Could not parse URL: ($url)"}
    }

    let path = (
        $remote.path
        | str trim --char "/"
        | str lowercase
        | str replace --regex '\.git$' ''
        | split row "/"
    )

    if ($remote.forge in [. ..]) or ($path | length) < 2 or ($path | any {|p| ($p | is-empty) or $p in [. ..] }) {
        return {error: $"Could not determine forge repo path from URL: ($url)"}
    }

    {parts: [$remote.forge ...$path]}
}

# Where a clone of URL lives.
export def target [url: string] {
    let repo = (parts $url)

    if ($repo.error? != null) {
        return $repo
    }

    let name = ($repo.parts | str join "/")
    let s = (settings)
    let root = (
        $s.roots
        | where {|r| $"($name)/" | str starts-with $r.prefix }
        | get --optional 0.root
        | default $s.base
        | path expand
    )

    {path: ($root | path join ...$repo.parts)}
}

# jj repos at or below DIR, without descending into repos.
export def find-repos [dir: path] {
    if ($dir | path join ".jj" | path exists) {
        return [$dir]
    }

    ls --all $dir | where type == dir | get name | par-each {|d| find-repos $d } | flatten
}

export def clones [] {
    all-roots
    | where ($it | path exists)
    | each {|root|
        find-repos $root | each {|path| {name: ($path | path relative-to $root), path: $path} }
    }
    | flatten
    | sort-by name
}

export def matching [query?: string, --exact] {
    let all = (clones)

    if ($query | is-empty) {
        return $all
    }

    let query = ($query | str lowercase | str trim --char "/")

    if $exact {
        $all | where {|c|
            let name = ($c.name | str lowercase)
            let p = ($name | split row "/")
            $query in [($p | last) ($p | last 2 | str join "/") $name]
        }
    } else {
        $all | where ($it.name | str lowercase | str contains $query)
    }
}

export def complete-clones [] { clones | get name }

export def --env jump [found: list<record>, query?: string] {
    let chosen = match ($found | length) {
        0 => { error make {msg: $"No local clone matches ($query | default '')"} }
        1 => $found.0
        _ => ($found | input list --fuzzy --display name "repo")
    }

    if $chosen == null { return }
    cd $chosen.path
    $chosen.path
}

# Remove DIR's parents that are left empty, up to the root holding it.
export def prune-empty [dir: path] {
    let stop = (all-roots)
    mut dir = ($dir | path dirname)

    while $dir not-in $stop and ($dir | path exists) and (ls -a $dir | is-empty) {
        rm $dir
        $dir = ($dir | path dirname)
    }
}

# Whether the workspace at DIR is the only one using its repo, so that removing
# or moving it breaks no other workspace.
export def sole-workspace [dir: path] {
    let ws = (
        do { ^jj workspace list --ignore-working-copy -R $dir -T 'if(self.current_workspace(), "*", "") ++ name ++ "\n"' }
        | complete
    )
    $ws.exit_code == 0 and ($ws.stdout | lines | length) == 1 and ($ws.stdout | str starts-with "*")
}

# PATH relative to the base dir, or in full if it's located elsewhere.
export def show [path: path] {
    try { $path | path relative-to (base-dir) } catch { $path }
}

export def remote-url [host: string, path: list<string>, ssh: bool] {
    let path = ($path | str join "/")
    if $ssh { $"git@($host):($path).git" } else { $"https://($host)/($path)" }
}

# Turn a <repo> spec into {url, path}, or {path} for a bare name that matches
# exactly one local clone.
export def resolve [spec: string, ssh: bool] {
    if (is-url $spec) {
        let target = (target $spec)
        if ($target.error? != null) { error make {msg: $target.error} }
        return {url: $spec, path: $target.path}
    }

    let p = ($spec | str trim --char "/" | split row "/")
    let s = (settings)

    if ($p | length) == 1 {
        let local = (matching --exact $spec)
        if ($local | length) == 1 {
            return {path: $local.0.path}
        }
    }

    if ($p | length) == 1 and $s.owner == null {
        error make {msg: $"($spec) matches no single local clone, please give owner/($spec), or set `owner` in (config-path)"}
    }

    let url = match ($p | length) {
        1 => (remote-url $s.host [$s.owner $p.0] $ssh)
        _ if ($p.0 | str contains ".") => (remote-url $p.0 ($p | skip 1) $ssh)
        _ => (remote-url $s.host $p $ssh)
    }

    {url: $url, path: (target $url).path}
}
