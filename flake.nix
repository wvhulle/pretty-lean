{
  description = "Lean development flake. Not intended for end users.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = inputs: builtins.foldl' inputs.nixpkgs.lib.attrsets.recursiveUpdate {} (builtins.map (system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      llvmPackages = pkgs.llvmPackages_19;
    in {
      devShells.${system} = {
        # The default development shell for working on lean itself
        default = pkgs.mkShell.override {
          stdenv = pkgs.overrideCC pkgs.stdenv llvmPackages.clang;
        } {
          buildInputs = with pkgs; [
            cmake gmp libuv ccache pkg-config
            llvmPackages.bintools  # wrapped lld
            llvmPackages.llvm  # llvm-symbolizer for asan/lsan
            gdb
            tree  # for CI
          ];
          # https://github.com/NixOS/nixpkgs/issues/60919
          hardeningDisable = [ "all" ];
          # more convenient `ctest` output
          CTEST_OUTPUT_ON_FAILURE = 1;
        };
      };
    }) ["x86_64-linux" "aarch64-linux" "aarch64-darwin"]);
}
