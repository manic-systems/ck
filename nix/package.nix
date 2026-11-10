{
  lib,
  stdenvNoCC,
  makeBinaryWrapper,
  nushell,
}:
stdenvNoCC.mkDerivation {
  pname = "ck";
  version = "0.1.0";

  __structuredAttrs = true;

  src =
    let
      fs = lib.fileset;
      s = ../.;
    in
    fs.toSource {
      root = s;
      fileset = s + /ck;
    };

  strictDeps = true;
  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall

    module="$out/share/nushell/ck"
    install -Dm644 -t "$module" ck/*.nu

    # Nushell autoloads share/nushell/vendor/autoload from
    # every profile on XDG_DATA_DIRS, so installing the package is enough.
    mkdir -p "$out/share/nushell/vendor/autoload"
    echo "use $module *" > "$out/share/nushell/vendor/autoload/ck.nu"

    # Everyone else gets a `ck` binary with the
    # same subcommands.
    install -Dm644 ck/mod.nu "$out/libexec/ck/ck"
    substituteInPlace "$out/libexec/ck/ck" \
      --replace-fail "use config.nu" "use $module/config.nu" \
      --replace-fail "use lib.nu" "use $module/lib.nu" \
      --replace-fail "use tidy.nu" "use $module/tidy.nu" \
      --replace-fail 'export def --env main [' 'def --env main [' \
      --replace-fail 'export def --env "ck ' 'def --env "main ' \
      --replace-fail 'export def "ck ' 'def "main '

    makeWrapper ${lib.getExe nushell} "$out/bin/ck" \
      --add-flags "$out/libexec/ck/ck"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ nushell ];
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR"
    nu --no-config-file --commands '
      let files = (glob $"($env.out)/share/nushell/**/*.nu" | append $"($env.out)/libexec/ck/ck")
      let bad = ($files | each {|file|
        nu --no-config-file --ide-check 100 $file
        | lines
        | each { from json }
        | where type == diagnostic
        | each {|d| print --stderr $"($file): ($d | to json --raw)"; $d }
      } | flatten)
      if ($bad | is-not-empty) { exit 1 }
    '

    runHook postInstallCheck
  '';

  meta = {
    description = "Keep your jj clones in one layout, and in order";
    homepage = "https://github.com/manic-systems/ck";
    license = lib.licenses.eupl12;
    mainProgram = "ck";
    platforms = lib.platforms.unix;
  };
}
