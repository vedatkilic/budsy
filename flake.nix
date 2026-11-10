# Installs the released, notarized Budsy.app (prebuilt, Apple Silicon only).
#
# Like the Homebrew cask (homebrew/budsy.rb), `version` and `hash` are bumped
# on every release. Get the hash with
#   nix store prefetch-file https://github.com/vedatkilic/budsy/releases/download/v<version>/Budsy-<version>.zip
# or copy the "SRI (flake.nix)" line package.sh prints.
{
  description = "Budsy: menu-bar controller for Samsung Galaxy Buds";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      budsy = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "budsy";
        version = "1.6.2";

        src = pkgs.fetchurl {
          url = "https://github.com/vedatkilic/budsy/releases/download/v${version}/Budsy-${version}.zip";
          hash = "sha256-LvTDe9aHyG2UVEyGBmZCYlledWFrRR2WDgUITgRmZTw=";
        };

        # The release dmg is APFS, which undmg can't read, so each release also
        # ships the stapled app as a zip; unzip keeps the bundle intact.
        nativeBuildInputs = [ pkgs.unzip ];
        sourceRoot = ".";

        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications
          cp -R Budsy.app $out/Applications/
          runHook postInstall
        '';

        # Patching would break the Developer ID signature and notarization staple.
        dontFixup = true;

        meta = {
          description = "Menu-bar controller for Samsung Galaxy Buds";
          homepage = "https://github.com/vedatkilic/budsy";
          license = lib.licenses.mit;
          platforms = [ system ];
          sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        };
      };
    in
    {
      packages.${system} = {
        inherit budsy;
        default = budsy;
      };
    };
}
