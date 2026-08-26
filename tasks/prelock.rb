require_relative "security_capabilities"

# Locks the Datadog-owned gems a lockfile cannot already satisfy, with cooldown
# disabled.
#
# Lives outside `dependency.rake` so `lock-dependency.yml` can run it before
# `bundle install`, where loading the Rakefile would fail on its development
# requires. Must stay loadable with only stdlib and Bundler available.
module Prelock
  module_function

  # `env` is passed explicitly because it survives `with_unbundled_env`, which
  # strips ambient `BUNDLE_*`.
  def call(gemfile)
    return unless SecurityCapabilities.for_version(RUBY_VERSION)[:cooldown]

    dependencies = SecurityCapabilities.uncooled_prelock_dependencies(
      "#{gemfile}.lock",
      SecurityCapabilities.first_party_dependencies,
    )
    return if dependencies.empty?

    command = "bundle lock --update #{dependencies.map(&:name).join(" ")}"
    env = {"BUNDLE_GEMFILE" => gemfile.to_s, "BUNDLE_COOLDOWN" => "0"}

    Bundler.with_unbundled_env do
      puts command
      raise "Failed: #{command}" unless system(env, command)
    end
  end
end
