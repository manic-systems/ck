{
  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsForEach = nixpkgs.legacyPackages;
    in
    {
      packages = forEachSystem (system: {
        ck = pkgsForEach.${system}.callPackage ./nix/package.nix { };
        default = self.packages.${system}.ck;
      });

      devShells = forEachSystem (system: {
        default = pkgsForEach.${system}.mkShellNoCC {
          packages = with pkgsForEach.${system}; [
            nushell
            jujutsu
            nixfmt
          ];
        };
      });
    };
}
