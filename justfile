# Tasks for this pocopine app. Run `just` to list, `just <recipe>` to run one.
# Install just: https://github.com/casey/just  (or `cargo install just`)

# show available recipes
default:
    @just --list

# build + serve with live reload (the everyday loop)
dev:
    pocopine dev

# production build — wasm bundle + Pine Stylekit CSS
build:
    pocopine build --release

# serve the built app
serve:
    pocopine run

# check the local toolchain + project config
doctor:
    pocopine doctor

# one-time prerequisites: the wasm target + wasm-pack
setup:
    rustup target add wasm32-unknown-unknown
    cargo install wasm-pack

# refresh the living agent guides in .claude/skills/ (pocopine-skills repo)
skills:
    pocopine skills update

# format Rust
fmt:
    cargo fmt

# type-check without building wasm
check:
    cargo check

# remove build output
clean:
    rm -rf target pkg
