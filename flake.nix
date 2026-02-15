{
  description = "Lean 4 theorem prover and programming language";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    nixpkgs-old.url = "https://channels.nixos.org/nixos-19.03/nixexprs.tar.xz";
    nixpkgs-old.flake = false;
    nixpkgs-older.url = "https://channels.nixos.org/nixos-18.03/nixexprs.tar.xz";
    nixpkgs-older.flake = false;
  };

  outputs = inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # Mimalloc source - used by all builds
      mimallocSrc = pkgs: pkgs.fetchFromGitHub {
        owner = "microsoft";
        repo = "mimalloc";
        rev = "v2.2.3";
        sha256 = "sha256-B0gngv16WFLBtrtG5NqA2m5e95bYVcQraeITcOX9A74=";
      };

      # Per-system outputs
      forSystem = system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          pkgsDist-old = import inputs.nixpkgs-older { inherit system; };
          pkgsDist-old-aarch = import inputs.nixpkgs-old {
            localSystem.config = "aarch64-unknown-linux-gnu";
          };

          # ============ Lean Package Builder ============

          lean-all = pkgs.stdenv.mkDerivation {
            pname = "lean";
            version = "4.28.0-pre";
            src = inputs.self;

            nativeBuildInputs = with pkgs; [ cmake git pkg-config ];
            buildInputs = with pkgs; [ gmp libuv ];

            sourceRoot = "source";

            # Set up mimalloc before configure
            preConfigure = ''
              mkdir -p mimalloc/src
              cp -r ${mimallocSrc pkgs} mimalloc/src/mimalloc
              chmod -R u+w mimalloc
              cd src
            '';

            cmakeFlags = [
              "-DCMAKE_BUILD_TYPE=Release"
              "-DSTAGE=1"
              "-DPREV_STAGE=${inputs.self}/stage0"
              "-DUSE_GITHASH=ON"
              "-DGIT_SHA1=${inputs.self.rev or inputs.self.dirtyRev or "unknown"}"
              "-DINSTALL_LICENSE=ON"
              "-DINSTALL_CADICAL=ON"
              "-DUSE_MIMALLOC=ON"
              "-DUSE_LAKE=ON"
            ];

              postFixup = ''
                # Make binaries find libraries via relative rpath
                for exe in $out/bin/*; do
                  if [ -x "$exe" ] && [ -f "$exe" ] && ! [ -L "$exe" ]; then
                    ${pkgs.patchelf}/bin/patchelf \
                      --set-rpath "$ORIGIN/../lib/lean" "$exe" 2>/dev/null || true
                  fi
                done

                # Make libraries find each other
                if [ -d $out/lib/lean ]; then
                  for lib in $out/lib/lean/*.so*; do
                    if [ -f "$lib" ] && ! [ -L "$lib" ]; then
                      ${pkgs.patchelf}/bin/patchelf \
                        --set-rpath "$ORIGIN" "$lib" 2>/dev/null || true
                    fi
                  done
                fi
              '';

              meta = with pkgs.lib; {
                description = "Lean 4 theorem prover and programming language";
                homepage = "https://lean-lang.org";
                license = licenses.asl20;
                platforms = platforms.linux;
                mainProgram = "lean";
              };
            };

          # ============ Development Shells ============

          mkDevShell = pkgsDist:
            pkgs.mkShell.override {
              stdenv = pkgs.overrideCC pkgs.stdenv pkgs.llvmPackages_15.clang;
            } ({
              buildInputs = with pkgs; [
                cmake gmp libuv ccache pkg-config
                llvmPackages_15.bintools
                llvmPackages_15.llvm
                gdb tree
              ];
              hardeningDisable = [ "all" ];
              CTEST_OUTPUT_ON_FAILURE = 1;
            } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              GMP = (pkgsDist.gmp.override { withStatic = true; }).overrideAttrs (
                pkgs.lib.optionalAttrs (pkgs.stdenv.system == "aarch64-linux") {
                  hardeningDisable = [ "stackprotector" ];
                }
              );
              LIBUV = pkgsDist.libuv.overrideAttrs {
                configureFlags = [ "--enable-static" ];
                hardeningDisable = [ "stackprotector" ];
                version = "1.48.0";
                src = pkgs.fetchFromGitHub {
                  owner = "libuv";
                  repo = "libuv";
                  rev = "v1.48.0";
                  sha256 = "100nj16fg8922qg4m2hdjh62zv4p32wyrllsvqr659hdhjc03bsk";
                };
                doCheck = false;
              };
              GLIBC = pkgsDist.glibc;
              GLIBC_DEV = pkgsDist.glibc.dev;
              GCC_LIB = pkgsDist.gcc.cc.lib;
              ZLIB = pkgsDist.zlib;
              GDB = pkgsDist.gdb;
            });

        in {
          packages.${system} = {
            inherit lean-all;
            default = lean-all;
          };

          devShells.${system} = {
            default = mkDevShell pkgs;
            oldGlibc = mkDevShell pkgsDist-old;
            oldGlibcAArch = mkDevShell pkgsDist-old-aarch;
          };
        };

    in builtins.foldl'
      inputs.nixpkgs.lib.attrsets.recursiveUpdate
      {}
      (builtins.map forSystem systems);
}
