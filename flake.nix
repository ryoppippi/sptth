{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      rust-overlay,
      crane,
      treefmt-nix,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          overlays = [ (import rust-overlay) ];
          pkgs' = import inputs.nixpkgs { inherit system overlays; };
          rustToolchain = pkgs'.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          craneLib = (crane.mkLib pkgs').overrideToolchain rustToolchain;

          src = craneLib.cleanCargoSource ./.;
          commonArgs = {
            inherit src;
            strictDeps = true;
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
              pkgs.apple-sdk
            ];
          };
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          sptth = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });

          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs.rustfmt.enable = true;
            programs.nixfmt.enable = true;
            settings.formatter.oxfmt = {
              command = "${pkgs.oxfmt}/bin/oxfmt";
              options = [ "--no-error-on-unmatched-pattern" ];
              includes = [ "*" ];
              excludes = [ "flake.lock" ];
            };
          };
        in
        {
          packages = {
            default = sptth;
            sptth = sptth;
          };

          checks = {
            inherit sptth;
            cargoClippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );
            cargoTest = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
            formatting = treefmtEval.config.build.check inputs.self;
          };

          formatter = treefmtEval.config.build.wrapper;

          devShells.default = craneLib.devShell {
            inputsFrom = [ sptth ];
          };
        };
    };
}
