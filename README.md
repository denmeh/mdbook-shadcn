# mdbook-shadcn

A patch-based fork of [mdBook](https://github.com/rust-lang/mdBook). This repository does not vendor upstream sources. It stores numbered git patches and rebuilds a working tree from a pinned mdBook commit.

Licensed under the [Mozilla Public License 2.0](LICENSE), same as mdBook.

## Setup

```bash
git clone https://github.com/denmeh/mdbook-shadcn.git
cd mdbook-shadcn
./scripts/apply.sh
```

That clones `rust-lang/mdBook` at the SHA in `upstream.conf` into `work/mdbook` (gitignored) and applies every file in `patches/`. If that tree is already up to date, apply does nothing so local edits are not wiped. `./scripts/apply.sh --status` prints what is applied; `--force` wipes and replays.

Build and run from the work tree:

```bash
cargo build --manifest-path work/mdbook/Cargo.toml
./work/mdbook/target/debug/mdbook-shadcn --help
```

Install from the applied tree:

```bash
cargo install --path work/mdbook
```

## Patch workflow

1. Apply patches: `./scripts/apply.sh`
2. Edit files in `work/mdbook`
3. Commit **inside** that nested repo (`git -C work/mdbook add -A && git -C work/mdbook commit`)
4. Export commits back to `patches/`: `./scripts/rebuild.sh`
5. Commit the updated `.patch` files in this repository

Each commit after the pinned upstream SHA becomes one numbered patch. Keep changes small so rebases onto newer mdBook releases stay reviewable.

Internal crates (`mdbook-core`, `mdbook-html`, `mdbook-driver`, …) keep their upstream names. Only the published CLI package is `mdbook-shadcn`.

## Updating upstream

Change the `sha` (and `ref`) in `upstream.conf`, run `./scripts/apply.sh`, resolve any `git am` conflicts in `work/mdbook`, then `./scripts/rebuild.sh`.
