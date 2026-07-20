require_relative "security_capabilities"

# Checks presence (not correctness) of a lockfile's CHECKSUMS section against
# whether SecurityCapabilities says that lockfile's Ruby is checksum-eligible.
#
# This is a static text scan, no Bundler API calls: `bundle lock
# --add-checksums` (see tasks/dependency.rake) is what actually populates the
# section; this module only verifies the field didn't silently disappear
# (e.g. regenerated on an old Bundler, or hand-edited).
module ChecksumScanning
  module_function

  # Returns an Array of Hash: { lockfile:, problem: } for every lockfile that
  # doesn't match its expected checksum state. Empty Array means clean.
  # problem is :missing_checksums or :unexpected_checksums.
  def findings(lockfile_paths)
    lockfile_paths.each_with_object([]) do |path, findings|
      eligible = SecurityCapabilities.checksum_eligible_lockfile?(File.basename(path))
      has_checksums = has_checksums_section?(path)

      if eligible && !has_checksums
        findings << {lockfile: path, problem: :missing_checksums}
      elsif !eligible && has_checksums
        findings << {lockfile: path, problem: :unexpected_checksums}
      end
    end
  end

  def has_checksums_section?(lockfile_path)
    File.readlines(lockfile_path).any? { |line| line.strip == "CHECKSUMS" }
  end
end
