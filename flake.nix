{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/release-25.05";
    flakelight.url = "github:nix-community/flakelight";
    spire.url = "git+https://codeberg.org/spire/nix";
    flakelight.inputs.nixpkgs.follows = "nixpkgs";
    spire.inputs.flakelight.follows = "flakelight";
  };

  outputs = {
    nixpkgs,
    utils,
    spire,
    ...
  }:
    utils.lib.eachSystem ["x86_64-linux" "i686-linux"] (system: let
      overlays = [spire.overlays.default];
      pkgs = (import nixpkgs) {
        inherit system overlays;
      };
      spEnv = pkgs.sourcepawn.buildEnv (with pkgs.sourcepawn.includes; [sourcemod curl]);
    in {
      packages = rec {
        mapdownloader = pkgs.buildSourcePawnScript {
          name = "mapdownloader";
          src = ./plugin/mapdownloader.sp;
          includes = with pkgs.sourcepawn.includes; [curl];
        };
        default = mapdownloader;
      };
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [spEnv];
      };
    });
}
