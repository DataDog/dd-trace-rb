require "pathname"

# Single source of truth for which Ruby runtimes support which supply-chain
# security features, and which lockfiles are eligible for the dependency audit.
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

  def for_version(version_string)
    version = Gem::Version.new(version_string)
    {
      audit: version >= AUDIT_MIN_VERSION,
      checksum: version >= CHECKSUM_MIN_VERSION,
      cooldown: version >= COOLDOWN_MIN_VERSION,
    }
  end

  # All lockfiles eligible for the dependency audit: the underscore appraisal
  # variants (ruby_X.Y_*.gemfile.lock) and the dash base lockfiles
  # (ruby-X.Y.gemfile.lock), for every audit-eligible Ruby version.
  def audit_eligible_lockfiles(gemfiles_dir = "gemfiles")
    dir = Pathname.new(gemfiles_dir)
    lockfiles = Dir.glob(dir.join("*.gemfile.lock").to_s)
    eligible = lockfiles.select { |path| audit_eligible_lockfile?(File.basename(path)) }
    eligible.sort
  end

  # A lockfile is eligible when its embedded Ruby version is audit-capable.
  # Handles both "ruby_3.1_contrib.gemfile.lock" and "ruby-3.1.gemfile.lock".
  def audit_eligible_lockfile?(basename)
    match = basename.match(/\Aruby[_-](\d+\.\d+)/)
    return false unless match

    for_version(match[1])[:audit]
  end
end
