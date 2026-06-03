# The correct gemfile is loaded based on current Ruby version and engine and generating
# `Gemfile.lock` at the root of the project.
#
# NOTE:
# After changing Ruby version, `Gemfile.lock` can become stale.
# Regenerate `Gemfile.lock` by running `rm Gemfile.lock && bundle lock`.
#
# If you are not familiar with handling multiple Ruby versions. It is recommended
# to used `docker compose` for development, which already handles the Ruby version for you.

# The gemspec is declared inside each per-Ruby base gemfile under gemfiles/
# (as `gemspec path: '..'`). That allows those files to be loaded directly via
# `BUNDLE_GEMFILE=gemfiles/ruby-X.Y.gemfile` and still resolve datadog.gemspec.

versioned_gemfile = "gemfiles/#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION[0, 3]}.gemfile"
versioned_lockfile = Pathname.new(File.expand_path("#{versioned_gemfile}.lock", __dir__))

if respond_to?(:lockfile)
  lockfile "#{versioned_gemfile}.lock"
else
  Bundler.define_singleton_method(:default_lockfile) { versioned_lockfile }

  define_singleton_method(:to_definition) do |_lockfile, unlock|
    super(versioned_lockfile, unlock)
  end
end

eval_gemfile(versioned_gemfile)
