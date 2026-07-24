require_relative "security_capabilities"

# A gemfile lockfile that knows its own embedded Ruby version and can answer
# whether it's eligible for a given supply-chain security feature, instead of
# callers checking eligibility against a bare path/basename externally.
#
# Basenames look like "ruby_3.1_contrib.gemfile.lock" (appraisal variant) or
# "ruby-3.1.gemfile.lock" (dash base lockfile).
class Lockfile
  VERSION_PATTERN = /\Aruby[_-](\d+\.\d+)/

  attr_reader :path

  def initialize(path)
    @path = path
  end

  def audit_eligible?
    capable?(:audit)
  end

  def checksum_eligible?
    capable?(:checksum)
  end

  def has_checksums_section?
    File.readlines(path).any? { |line| line.strip == "CHECKSUMS" }
  end

  private

  def capable?(capability)
    match = File.basename(path).match(VERSION_PATTERN)
    return false unless match

    SecurityCapabilities.for_version(match[1])[capability]
  end
end
