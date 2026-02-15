{
  description = "Lean 4 theorem prover and programming language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      # Keep in sync with src/CMakeLists.txt LEAN_VERSION_*
      version = "4.28.0-pre";

      eachSystem = f: builtins.foldl' nixpkgs.lib.recursiveUpdate { } (map f systems);
    in
    eachSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib stdenv;

        gitSha1 = self.rev or self.dirtyRev or "unknown";

        setupMimalloc = ''
          mkdir -p mimalloc/src
          cp -r ${pkgs.mimalloc.src} mimalloc/src/mimalloc
          chmod -R u+w mimalloc
        '';

        commonCmakeFlags = [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DUSE_MIMALLOC=ON"
          "-DLEAN_EXTRA_CXX_FLAGS=-Wno-array-bounds"
        ];

        mkLeanDerivation =
          attrs:
          stdenv.mkDerivation (
            {
              nativeBuildInputs = [
                pkgs.cmake
                pkgs.git
                pkgs.pkg-config
              ];
              buildInputs = [
                pkgs.gmp
                pkgs.libuv
              ];
              preBuild = "patchShebangs .";
              preInstall = "rm -f src/lean";
            }
            // attrs
          );

        srcFiles = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.unions [
            ./src
            ./LICENSE
            ./LICENSES
          ];
        };

        # Assert that the Nix-side version matches what CMake configured.
        checkVersion = ''
          cmake_version=$(sed -n 's/.*LEAN_VERSION_STRING "\(.*\)"/\1/p' include/lean/version.h)
          if [ "$cmake_version" != "${version}" ]; then
            echo "error: flake.nix version (${version}) != CMake version ($cmake_version)"
            echo "Update the 'version' variable in flake.nix to match src/CMakeLists.txt"
            exit 1
          fi
        '';

        # Expose a single binary from stage1 as its own package.
        mkToolWrapper =
          name:
          pkgs.runCommand "${name}-${version}" { meta.mainProgram = name; } ''
            mkdir -p $out/bin
            ln -s ${stage1}/bin/${name} $out/bin/${name}
          '';

        stage0 = mkLeanDerivation {
          pname = "lean-stage0";
          inherit version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = ./stage0;
          };
          sourceRoot = "source/stage0/src";
          preConfigure = setupMimalloc;
          cmakeFlags = commonCmakeFlags ++ [
            "-DSTAGE=0"
            "-DUSE_GITHASH=OFF"
          ];
          meta.license = lib.licenses.asl20;
          meta.platforms = lib.platforms.linux;
        };

        stage1 = mkLeanDerivation {
          pname = "lean";
          inherit version;
          src = srcFiles;
          sourceRoot = "source/src";
          preConfigure = setupMimalloc;
          postConfigure = checkVersion;
          # Stage2 needs these from PREV_STAGE; default install rules exclude them.
          postInstall = ''
            mkdir -p $out/runtime $out/lib/temp
            cp runtime/libleanrt_initial-exec.a $out/runtime/
            cp lib/temp/libleancpp_1.a $out/lib/temp/
          '';
          cmakeFlags = commonCmakeFlags ++ [
            "-DSTAGE=1"
            "-DPREV_STAGE=${stage0}"
            "-DUSE_GITHASH=ON"
            "-DGIT_SHA1=${gitSha1}"
            "-DINSTALL_LICENSE=ON"
            "-DINSTALL_CADICAL=ON"
            "-DUSE_LAKE=ON"
          ];
          meta = {
            description = "Lean 4 theorem prover and programming language";
            homepage = "https://lean-lang.org";
            license = lib.licenses.asl20;
            platforms = lib.platforms.linux;
            mainProgram = "lean";
          };
        };

        stage2 = mkLeanDerivation {
          pname = "lean-stage2";
          inherit version;
          src = srcFiles;
          sourceRoot = "source/src";
          preConfigure = setupMimalloc;
          cmakeFlags = commonCmakeFlags ++ [
            "-DSTAGE=2"
            "-DPREV_STAGE=${stage1}"
            "-DUSE_GITHASH=ON"
            "-DGIT_SHA1=${gitSha1}"
            "-DINSTALL_LICENSE=ON"
            "-DINSTALL_CADICAL=ON"
            "-DUSE_LAKE=ON"
          ];
          meta = {
            description = "Lean 4 stage2 self-hosted toolchain";
            license = lib.licenses.asl20;
            platforms = lib.platforms.linux;
            mainProgram = "lean";
          };
        };

      in
      {
        packages.${system} = {
          inherit stage0 stage1 stage2;
          default = stage1;
          lean = mkToolWrapper "lean";
          lake = mkToolWrapper "lake";
          leanc = mkToolWrapper "leanc";
          leanchecker = mkToolWrapper "leanchecker";
          leanmake = mkToolWrapper "leanmake";
        };

        devShells.${system}.default =
          (pkgs.mkShell.override {
            stdenv = pkgs.overrideCC stdenv pkgs.llvmPackages.clang;
          })
            {
              buildInputs = [
                pkgs.cmake
                pkgs.gmp
                pkgs.libuv
                pkgs.ccache
                pkgs.pkg-config
                pkgs.llvmPackages.bintools
                pkgs.llvmPackages.llvm
                pkgs.gdb
                pkgs.tree
              ];
              hardeningDisable = [ "all" ];
              MAKEFLAGS = "-j$(nproc)";
              CTEST_OUTPUT_ON_FAILURE = 1;
              STAGE0 = stage0;
            };
      }
    );
}
