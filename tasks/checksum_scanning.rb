require_relative "lockfile"

module ChecksumScanning
  module_function

  def findings(lockfile_paths)
    lockfile_paths.each_with_object([]) do |path, findings|
      eligible = Lockfile.new(path).checksum_eligible?
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
