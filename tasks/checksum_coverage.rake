require_relative "lockfile"

namespace :dependency do
  desc "Check that every checksum-eligible lockfile has a CHECKSUMS section"
  task :checksum_coverage do
    lockfiles = Dir.glob("gemfiles/*.gemfile.lock").map { |path| Lockfile.new(path) }.select(&:checksum_eligible?).sort_by(&:path)
    # TODO: this only checks for the CHECKSUMS section's presence, not that it has digest entries (see PR #6069 review).
    missing = lockfiles.reject(&:has_checksums_section?)

    if missing.empty?
      puts "Checksum coverage OK across #{lockfiles.size} lockfiles."
    else
      puts "Found #{missing.size} checksum coverage issue(s):"
      missing.each { |lockfile| puts "  #{lockfile.path}: missing expected CHECKSUMS section" }
      abort("Checksum coverage check failed.")
    end
  end
end
