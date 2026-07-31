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

  def for_version(version_string)
    version = Gem::Version.new(version_string)
    {
      audit: version >= AUDIT_MIN_VERSION,
      checksum: version >= CHECKSUM_MIN_VERSION,
      cooldown: version >= COOLDOWN_MIN_VERSION,
    }
  end
end
