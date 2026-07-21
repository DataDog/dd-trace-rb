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
eval_gemfile("gemfiles/#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION.split(".").take(2).join(".")}.gemfile")
