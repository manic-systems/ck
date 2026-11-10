# Settings for ck, read from a NUON file over these defaults. The file is
# $env.CK_CONFIG if set, else $XDG_CONFIG_HOME/ck/config.nuon.

const defaults = {
    base: "~/git"                                # root of the layout
    host: "github.com"                           # forge for owner/repo shorthands
    owner: null                                  # owner for bare repo shorthands
    me: []                                       # owners whose repos are your forks, for ck tidy; defaults to [owner]
    roots: []                                    # other roots by prefix: [{prefix: "github.com/acme/", root: "~/work"}]
    host_aliases: {}                             # dead SSH host aliases: {github-work: "github.com"}
    role_remotes: [origin upstream contrib fork] # remotes ck tidy treats as the project or your fork
}

export def config-path [] {
    $env.CK_CONFIG? | default {
        $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join ck config.nuon
    } | path expand
}

export def settings [] {
    let file = (config-path)
    let user = if ($file | path exists) { open --raw $file | from nuon } else { {} }
    let s = ($defaults | merge $user)
    let me = if ($s.me | is-empty) { [$s.owner] | compact } else { $s.me }
    $s | merge {me: $me, role_remotes: ($s.role_remotes | append $me | uniq)}
}
