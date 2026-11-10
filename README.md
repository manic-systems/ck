<!-- markdownlint-disable MD033 MD041 -->
<div align="center">
  <img src="assets/duck.jpg" alt="A duck" width="200"/>
  <h1 id="header">ck</h1>
  <a alt="License" href="https://github.com/manic-systems/ck/blob/main/LICENSE">
    <img
      src="https://img.shields.io/github/license/manic-systems/ck?label=License"
      alt="License"
    />
  </a>
  <br/>
  <h6>Because "du<u>ck</u>" was too long to type...</h6>
  <br/>
  <a href="#install">Install</a> | <a href="#settings">Settings</a>
  <br/>
</div>

&nbsp;

Keep your [jj](https://github.com/jj-vcs/jj) clones in one layout,
in one place, and in order.

> [!NOTE]
> This needs jj. If you don't use jj yet, go learn jj.
> jj is good. jj is great.
> I like jj.
>
> `ck fork` also needs `gh`, and `ck new --template` nix. Go cry about it.

## Tl;DR, because reading is hard

```nu
ck [query]             # jump to a local clone, fuzzy picking if several match
ck get <repo>          # clone, or jump to the existing clone
ck list [query]        # list local clones
ck rm <repo>           # remove a local clone
ck new <repo>          # start a new repo in the layout
ck fork                # fork origin on GitHub, add it as `contrib`
ck tidy                # move repos and fix remotes to match the layout
ck config              # show the settings in use
```

## Install

### Nix

Install `packages.<system>.ck` anywhere that puts it on `XDG_DATA_DIRS`, such
as `environment.systemPackages` or `users.users.<name>.packages`.

With flakes:

```nix
{
  inputs.ck.url = "github:manic-systems/ck";

  # in a NixOS module
  environment.systemPackages = [ inputs.ck.packages.${pkgs.stdenv.hostPlatform.system}.ck ];
}
```

With [tack](https://github.com/manic-systems/tack):

```sh
tack add ck github:manic-systems/ck
```

```nix
let
  inputs = import ./.tack;
in
{
  # in a NixOS module
  environment.systemPackages = [ inputs.ck.packages.${pkgs.stdenv.hostPlatform.system}.ck ];
}
```

The package ships `share/nushell/vendor/autoload/ck.nu`, which nushell loads by
itself. `ck` is therefore all you need, nice! It also ships a `ck` binary with the
same subcommands for scripts, agents (blegh) and other shells. To `cd` you _do_ need the nushell version, so `ck` and `ck get` only print or clone.

### By hand (why?????)

Clone the repo and add to your `config.nu`:

```nu
use /path/to/ck/ck *
```

## Settings

`ck` reads `$XDG_CONFIG_HOME/ck/config.nuon` (or `$env.CK_CONFIG`) over these
defaults:

```nuon
{
  base: "~/git"                     # root of the layout
  host: "github.com"                # forge for owner/repo shorthands
  owner: null                       # owner for bare repo shorthands
  me: []                            # owners whose repos are your forks, for ck tidy; defaults to [owner]
  roots: []                         # other roots by prefix: [{prefix: "github.com/acme/", root: "~/work"}]
  host_aliases: {}                  # dead SSH host aliases: {github-work: "github.com"}
  role_remotes: [origin upstream contrib fork]  # remotes ck tidy treats as the project or your fork
}
```

## License

EUPL-1.2
