module ChecksumScanning
  module_function

  # `lockfile_paths` is expected to already be filtered to checksum-eligible
  # lockfiles; this only checks for a missing CHECKSUMS section.
  def findings(lockfile_paths)
    lockfile_paths.each_with_object([]) do |path, findings|
      findings << {lockfile: path, problem: :missing_checksums} unless has_checksums_section?(path)
    end
  end

  def has_checksums_section?(lockfile_path)
    File.readlines(lockfile_path).any? { |line| line.strip == "CHECKSUMS" }
  end
end
