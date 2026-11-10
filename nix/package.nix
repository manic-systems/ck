{
  lib,
  stdenvNoCC,
  makeBinaryWrapper,
  nushell,
}:
stdenvNoCC.mkDerivation {
  pname = "ck";
  version = "0.1.0";

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

    # Interactive shells: nushell autoloads share/nushell/vendor/autoload from
    # every profile on XDG_DATA_DIRS, so installing the package is enough.
    mkdir -p "$out/share/nushell/vendor/autoload"
    echo "use $module *" > "$out/share/nushell/vendor/autoload/ck.nu"

    # Everyone else (scripts, agents, other shells) gets a `ck` binary with the
    # same subcommands. It cannot change its caller's directory, so `ck` and
    # `ck get` print the clone's path instead.
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

    export HOME="$TMPDIR" XDG_CONFIG_HOME="$TMPDIR/config"
    $out/bin/ck --help > /dev/null
    $out/bin/ck config > /dev/null
    nu --no-config-file --commands "source $out/share/nushell/vendor/autoload/ck.nu; ck config | ignore"

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
