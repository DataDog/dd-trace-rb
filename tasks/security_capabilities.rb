require "bundler"

# Single source of truth for which Ruby runtimes support which supply-chain
# security features.
#
# Loaded by rake on every Ruby (2.5-4.0), so it must stay 2.5-compatible.
# Tier boundaries mirror the supply-chain security design:
#   - audit    : Ruby 3.1+  (noise decision; legacy compat gems carry historical CVEs)
#   - checksum : Ruby 3.1+
#   - cooldown : Ruby 3.2+
module SecurityCapabilities
  module_function

  # Ruby versions eligible for each feature. Anything at or above the listed
  # floor is eligible; anything below is legacy (pinning only).
  AUDIT_MIN_VERSION = Gem::Version.new("3.1")
  CHECKSUM_MIN_VERSION = Gem::Version.new("3.1")
  COOLDOWN_MIN_VERSION = Gem::Version.new("3.2")
  COOLDOWN_DAYS = 2

  # Exempt from cooldown: it guards against a compromised upstream, which does
  # not apply to releases we cut ourselves, and their `~>` pins leave no older
  # fallback when a bump lands inside the window.
  FIRST_PARTY_GEMS = %w[
    datadog-ruby_core_source
    libdatadog
    libddwaf
  ].freeze

  def for_version(version_string)
    version = Gem::Version.new(version_string)
    {
      audit: version >= AUDIT_MIN_VERSION,
      checksum: version >= CHECKSUM_MIN_VERSION,
      cooldown: version >= COOLDOWN_MIN_VERSION,
    }
  end

  # Intersected with the gemspec rather than read straight off the constant:
  # `bundle lock --update` errors on a gem we no longer depend on.
  def first_party_dependencies(gemspec_path = "datadog.gemspec")
    Gem::Specification.load(gemspec_path).dependencies
      .select { |dependency| FIRST_PARTY_GEMS.include?(dependency.name) }
  end

  # Narrowed to the unsatisfied gems: naming a satisfied one would unlock it and
  # let an unrelated in-window release slip in.
  def uncooled_prelock_dependencies(lockfile, dependencies)
    return dependencies unless File.exist?(lockfile)

    specs = Bundler::LockfileParser.new(File.read(lockfile)).specs

    dependencies.select do |dependency|
      locked = specs.select { |spec| spec.name == dependency.name }
      locked.empty? || locked.any? { |spec| !dependency.requirement.satisfied_by?(spec.version) }
    end
  end
end
