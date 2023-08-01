{
  # use the environment channel
  pkgs ? import <nixpkgs> {},

  # use a pinned package state
  pinned ? import(fetchTarball("https://github.com/NixOS/nixpkgs/archive/88f63d51109.tar.gz")) {},
}:
let
  # specify ruby version to use
  ruby = pinned.ruby_3_2;

  # control llvm/clang version (e.g for packages built from source)
  llvm = pinned.llvmPackages_12;

  # control gcc version (e.g for packages built from source)
  gcc = pinned.gcc12;
in llvm.stdenv.mkDerivation {
  # unique project name for this environment derivation
  name = "dd-trace-rb.devshell";

  buildInputs = [
    ruby

    # for profiler
    pinned.pkgconfig

    # TODO: some gems insist on using `gcc` on Linux, satisfy them for now:
    # - json
    # - protobuf
    # - ruby-prof
    gcc
  ];

  shellHook = ''
    # get major.minor.0 ruby version
    export RUBY_VERSION="$(ruby -e 'puts RUBY_VERSION.gsub(/\d+$/, "0")')"

    # make gem install work in-project, compatibly with bundler
    export GEM_HOME="$(pwd)/vendor/bundle/ruby/$RUBY_VERSION"

    # make bundle work in-project
    export BUNDLE_PATH="$(pwd)/vendor/bundle"

    # enable calling gem scripts without bundle exec
    export PATH="$GEM_HOME/bin:$PATH"
  '';
}
