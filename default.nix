{
  system ? builtins.currentSystem,
  nixpkgs ? <nixpkgs>,
  pkgs ? import nixpkgs { inherit system; },
  lib ? pkgs.lib,
}: {
  packages = {
    luamin = pkgs.buildNpmPackage (finalAttrs: {
      pname = "luamin";
      version = "1.0.4";
      src = pkgs.fetchFromGitHub {
        owner = "mathiasbynens";
        repo = "luamin";
        rev = "v${finalAttrs.version}";
        hash = "sha256-uST/G59fFAfRcZaRNFZTysQUQ4eDUBhfcb8+PGBGl6Q=";
      };
      npmDepsHash = "sha256-D/qw51jy4wArqhuV2Tw6E6+qRPtP5eHsdvNcyuJDTQM=";
      postPatch = ''
        cp ${./nix/luamin-package-lock.json} package-lock.json
      '';
      dontNpmBuild = true;
      meta = {
        description = "Lua minifier written in JavaScript";
        homepage = "https://mths.be/luamin";
        license = lib.licenses.mit;
      };
    });
  };
}