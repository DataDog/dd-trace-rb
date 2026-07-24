require_relative "lockfile"
require_relative "checksum_scanning"

namespace :dependency do
  desc "Check that every checksum-eligible lockfile has a CHECKSUMS section"
  task :checksum_coverage do
    lockfiles = Dir.glob("gemfiles/*.gemfile.lock").select { |path| Lockfile.new(path).checksum_eligible? }.sort
    findings = ChecksumScanning.findings(lockfiles)

    if findings.empty?
      puts "Checksum coverage OK across #{lockfiles.size} lockfiles."
    else
      puts "Found #{findings.size} checksum coverage issue(s):"
      findings.each do |f|
        puts "  #{f[:lockfile]}: missing expected CHECKSUMS section"
      end
      abort("Checksum coverage check failed.")
    end
  end
end
