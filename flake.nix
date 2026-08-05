{
  description = "Vega Linux development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      swift = pkgs.stdenvNoCC.mkDerivation {
        pname = "swift";
        version = "6.1.3";

        src = pkgs.fetchurl {
          url = "https://download.swift.org/swift-6.1.3-release/ubuntu2204/swift-6.1.3-RELEASE/swift-6.1.3-RELEASE-ubuntu22.04.tar.gz";
          hash = "sha256-KOSySt+bG3grdZGdnyoLCtfhboQ6qiA+C6yngCSNzdY=";
        };

        # This is Swift's official Ubuntu 22.04 toolchain. Keep its binaries
        # linked against the host's compatible FHS runtime instead of mixing
        # Nixpkgs and Ubuntu glibc libraries.
        dontPatchELF = true;
        dontStrip = true;

        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp -R usr/. "$out/"
          runHook postInstall
        '';
      };
    in
    {
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          actionlint
          curl
          jq
          swift
        ];
      };
    };
}
