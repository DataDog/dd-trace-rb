require_relative "checksum_coverage"

namespace :dependency do
  desc "Check that every checksum-eligible lockfile has a CHECKSUMS section, and no legacy one does"
  task :checksum_coverage do
    lockfiles = Dir.glob("gemfiles/*.gemfile.lock")
    findings = ChecksumScanning.findings(lockfiles)

    if findings.empty?
      puts "Checksum coverage OK across #{lockfiles.size} lockfiles."
    else
      puts "Found #{findings.size} checksum coverage issue(s):"
      findings.each do |f|
        message = case f[:problem]
        when :missing_checksums
          "missing expected CHECKSUMS section"
        when :unexpected_checksums
          "has an unexpected CHECKSUMS section (not eligible for checksums)"
        end
        puts "  #{f[:lockfile]}: #{message}"
      end
      abort("Checksum coverage check failed.")
    end
  end
end
