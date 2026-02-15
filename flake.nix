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

        # -- Shared build configuration -----------------------------------------

        setupMimalloc = ''
          mkdir -p mimalloc/src
          cp -r ${pkgs.mimalloc.src} mimalloc/src/mimalloc
          chmod -R u+w mimalloc
        '';

        cmakeDeps = {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.git
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.gmp
            pkgs.libuv
          ];
        };

        commonCmakeFlags = [
          "-DCMAKE_BUILD_TYPE=Release"
          "-DUSE_MIMALLOC=ON"
          "-DLEAN_EXTRA_CXX_FLAGS=-Wno-array-bounds"
        ];

        mkLeanDerivation = attrs: stdenv.mkDerivation (cmakeDeps // attrs);

        # -- Stage 0: bootstrap compiler (cached separately) --------------------
        # Only rebuilds when stage0/ content changes. Since stage0 is updated
        # infrequently (chore: update stage0), this gives effective caching.

        stage0 = mkLeanDerivation {
          pname = "stage0";
          inherit version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = ./stage0;
          };
          sourceRoot = "source/stage0/src";
          preConfigure = setupMimalloc;
          preBuild = "patchShebangs .";
          preInstall = "rm -f src/lean";
          cmakeFlags = commonCmakeFlags ++ [
            "-DSTAGE=0"
            "-DUSE_GITHASH=OFF"
          ];
          meta.license = lib.licenses.asl20;
          meta.platforms = lib.platforms.linux;
        };

        # -- Stage 1: full Lean toolchain ---------------------------------------

        # Assert that the Nix-side version matches what CMake configured.
        # Catches stale version after a bump in src/CMakeLists.txt.
        checkVersion = ''
          cmake_version=$(sed -n 's/.*LEAN_VERSION_STRING "\(.*\)"/\1/p' include/lean/version.h)
          if [ "$cmake_version" != "${version}" ]; then
            echo "error: flake.nix version (${version}) != CMake version ($cmake_version)"
            echo "Update the 'version' variable in flake.nix to match src/CMakeLists.txt"
            exit 1
          fi
        '';

        stage1 = mkLeanDerivation {
          pname = "lean";
          inherit version;
          # Only include files needed for the stage1 build. Excludes stage0/,
          # tests/, flake.nix etc. so edits to those don't trigger a rebuild.
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./src
              ./LICENSE
              ./LICENSES
            ];
          };
          sourceRoot = "source/src";
          preConfigure = setupMimalloc;
          postConfigure = checkVersion;
          preBuild = "patchShebangs .";
          # CMake creates a symlink to the source dir for go-to-definition.
          # It becomes dangling after the sandbox is gone, so remove it
          # before install copies it into $out.
          preInstall = "rm -f src/lean";
          # Stage2+ needs these files from PREV_STAGE but the default
          # install rules exclude them. Copy them into $out.
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

        # -- Stage 2: self-hosted Lean toolchain ---------------------------------
        # Built with the stage1 compiler. Proves stage1 can compile itself.
        # Reuses C++ runtime from stage1; only recompiles Lean sources.

        stage2 = mkLeanDerivation {
          pname = "stage2";
          inherit version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./src
              ./LICENSE
              ./LICENSES
            ];
          };
          sourceRoot = "source/src";
          preConfigure = setupMimalloc;
          preBuild = "patchShebangs .";
          preInstall = "rm -f src/lean";
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

        # -- Development shell ---------------------------------------------------

        devShell =
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
              # Pre-built stage0 from Nix, so `cmake` skips the ~20min bootstrap
              STAGE0 = stage0;
            };

      in
      {
        packages.${system} = {
          inherit stage0 stage1 stage2;
          default = stage1;
        }
        // lib.genAttrs [ "lean" "lake" "leanc" "leanchecker" "leanmake" ] (
          name:
          stage1
          // {
            meta = stage1.meta // {
              mainProgram = name;
            };
          }
        );
        devShells.${system}.default = devShell;
      }
    );
}
