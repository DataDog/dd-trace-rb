{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";

    # cross-platform convenience
    flake-utils.url = "github:numtide/flake-utils";

    # backwards compatibility with nix-build and nix-shell
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz";
  };

  outputs = { self, nixpkgs, flake-utils, flake-compat }:
    # resolve for all platforms in turn
    flake-utils.lib.eachDefaultSystem (system:
      let
        # packages for this system platform
        pkgs = nixpkgs.legacyPackages.${system};

        # control versions
        ruby = pkgs.ruby_3_3;
        llvm = pkgs.llvmPackages_16;
        gcc = pkgs.gcc13;
      in {
        devShell = pkgs.llvm.stdenv.mkDerivation {
          name = "devshell";

          buildInputs = with pkgs; [
            ruby
            libyaml.dev

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

            # enable implicitly resolving gems to bundled version
            export RUBYGEMS_GEMDEPS="$(pwd)/Gemfile"
          '';
        };
      }
    );
}
