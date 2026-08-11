{
  description = "Vega development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          linuxSwift = pkgs.stdenvNoCC.mkDerivation {
            pname = "swift";
            version = "6.2.4";

            src = pkgs.fetchurl {
              url = "https://download.swift.org/swift-6.2.4-release/ubuntu2204/swift-6.2.4-RELEASE/swift-6.2.4-RELEASE-ubuntu22.04.tar.gz";
              hash = "sha256-qqoy8GCDj1xbR2r6rcuLSRcOjVskr+nLnfLozjPUp3g=";
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
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              actionlint
              curl
              jq
            ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ linuxSwift ];

            shellHook = pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              if ! command -v xcrun >/dev/null; then
                echo "Vega requires Xcode command-line tools on macOS." >&2
              fi
            '';
          };
        }
      );
    };
}
