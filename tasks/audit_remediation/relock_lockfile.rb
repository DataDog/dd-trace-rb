require 'bundler'

# Attempts to relock one lockfile's Gemfile against a set of gems, then
# re-scans to classify the result. Reverts the lockfile on both bundler
# failure and silent no-op (still-vulnerable) outcomes, since only a
# RESOLVED result is meant to be kept as a staged change.
module RelockLockfile
  module_function

  RESOLVED = :resolved
  UNRESOLVED = :unresolved
  ERROR = :error

  def attempt(lockfile_path, gems, database:, ignore:)
    gemfile_path = lockfile_path.sub(/\.lock\z/, '')
    original_contents = File.read(lockfile_path)

    begin
      success = Bundler.with_unbundled_env do
        system({'BUNDLE_GEMFILE' => gemfile_path}, "bundle lock --update #{gems.join(' ')}")
      end
      raise "bundle lock exited with status #{$?.exitstatus}" unless success
    rescue => e
      File.write(lockfile_path, original_contents)
      return {lockfile: lockfile_path, status: ERROR, remaining_findings: [], error_message: e.message}
    end

    remaining = DependencyAudit.high_critical_findings([lockfile_path], database: database, ignore: ignore)

    if remaining.empty?
      {lockfile: lockfile_path, status: RESOLVED, remaining_findings: []}
    else
      File.write(lockfile_path, original_contents)
      {lockfile: lockfile_path, status: UNRESOLVED, remaining_findings: remaining}
    end
  end
end
