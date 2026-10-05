require_relative "security_capabilities"

# A gemfile lockfile that knows its own embedded Ruby version, its companion
# gemfile, and whether it's eligible for a given supply-chain security feature,
# instead of callers checking eligibility against a bare path/basename
# externally.
#
# Basenames look like "ruby_3.1_contrib.gemfile.lock" (appraisal variant) or
# "ruby-3.1.gemfile.lock" (dash base lockfile).
class Lockfile
  VERSION_PATTERN = /\Aruby[_-](\d+\.\d+)/
  LOCK_EXTENSION = ".gemfile.lock"

  attr_reader :path

  def initialize(path)
    raise ArgumentError, "Lockfile path must end with #{LOCK_EXTENSION}: #{path}" unless path.end_with?(LOCK_EXTENSION)

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

  def gemfile_path
    path.chomp(".lock")
  end

  def orphaned?
    !File.exist?(gemfile_path)
  end

  def self.orphaned_lockfile_paths(dir)
    Dir.glob(File.join(dir, "*#{LOCK_EXTENSION}")).select { |path| new(path).orphaned? }.sort
  end

  private

  def capable?(capability)
    match = File.basename(path).match(VERSION_PATTERN)
    return false unless match

    SecurityCapabilities.for_version(match[1])[capability]
  end
end
