# Lean - Nix Edition

Fork of the [official Lean repo](https://github.com/leanprover/lean4) with some minor changes (for easy testing):

- Improved caching in `flake.nix` for [Nix package manager](https://wiki.nixos.org/wiki/Flake) users: separated `stage0` (C-only) and `stage1` (Lean) build
- Installation of standalone Lake binaries with `lake install`

Available binaries:

| Package       | Description                                    |
| ------------- | ---------------------------------------------- |
| `lean`        | Lean compiler (alias for `stage1`)             |
| `lake`        | Lake build tool (same derivation, runs `lake`) |
| `leanc`       | Lean C compiler wrapper                        |
| `leanchecker` | Lean proof checker                             |
| `leanmake`    | Lean make tool                                 |

## Installation

Add this repo as a Flake input to any of your Flake-based Nix projects:

```nix
{
  inputs.lean4.url = "github:wvhulle/lean4";

  outputs = { nixpkgs, lean4, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      lean = lean4.packages.x86_64-linux;
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [ lean.lake ]; # includes lean, lake, leanc, leanchecker
      };
    };
}
```

## Usage

Run the Lean binaries directly without installing them permanently:

- `nix run .#lean`: runs lean
- `nix run .#lake`: runs lake

The first time, this might take very long as `stage0` needs to be built (+20 minutes). Builds are cached until you do a Nix garbage collection.

Some more commands you can try:

- `nix run .#leanc`: runs leanc
- `nix run .#leanchecker`: runs leanchecker
- `nix run .#leanmake`: runs leanmake

I recommend installing `direnv` and creating a `.envrc` file:

```bash
use flake
```

## Development

### Structure

The Nix flake outputs are named after upstream conventions. Lean compilation is split into several stages. Each stage is mapped to a Nix build target that can be cached by Nix.

| Package   | Description                           |
| --------- | ------------------------------------- |
| `stage0`  | Bootstrap compiler (from C sources)   |
| `stage1`  | Full toolchain built by stage0        |
| `stage2`  | Self-hosted rebuild (built by stage1) |
| `default` | Alias for `stage1`                    |

All tool packages (`lean`, `lake`, `leanc`, `leanchecker`, `leanmake`) are the same derivation with a different entry point. Building any one of them gives you the complete toolchain.

### Development Builds

`nix build` always builds from scratch in a sandbox. Use the Nix dev shell when working on the Lean codebase (and ignoring the part of `stage0`):

```bash
nix develop
```

Configure with Nix-cached `stage0` (skips ~20min bootstrap):

```bash
cmake -S . -B build/release \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_MIMALLOC=ON \
  -DSTAGE1_PREV_STAGE=$STAGE0

# Build stage1
make -C build/release stage1
```

The dev shell sets `MAKEFLAGS="-j$(nproc)"` automatically, so all `make` invocations use full parallelism.

After editing `src/*`, just re-run `make` to re-use the `stage0` cache:

```bash
make -C build/release stage1
```

### Ignoring Nix `stage0` Cache

The dev shell sets `$STAGE0` to the Nix-cached stage0 output. To build stage0 from source instead (e.g. when hacking on `stage0/`), omit `-DSTAGE1_PREV_STAGE`:

```bash
cmake -S . -B build/release \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_MIMALLOC=ON
```

## Related

This project primary serves as an easy way for me to hack on the upstream Lean codebase while using Nix.

Try some of my other Lean projects:

- [Lean-TUI](https://codeberg.org/wvhulle/lean-tui): terminal-only info view for proof visualization
