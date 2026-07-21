require 'bundler'

# Attempts to relock one lockfile's Gemfile against a set of gems, then
# re-scans to classify the result. Gems are relocked one at a time against
# the running lockfile state so a fix for one gem is kept even when another
# gem in the same lockfile has no available fix -- reverting the whole
# lockfile whenever any single gem failed would silently discard genuine
# partial progress. Only a gem whose individual relock still leaves it (or
# a new advisory) flagged gets reverted; the final status reflects whatever
# high/critical findings remain after all gems have been attempted.
module RelockLockfile
  module_function

  RESOLVED = :resolved
  UNRESOLVED = :unresolved
  ERROR = :error

  def attempt(lockfile_path, gems, database:, ignore:)
    gemfile_path = lockfile_path.sub(/\.lock\z/, '')
    errors = {}

    gems.each do |gem_name|
      before_contents = File.read(lockfile_path)

      begin
        success = Bundler.with_unbundled_env do
          system({'BUNDLE_GEMFILE' => gemfile_path}, "bundle lock --update #{gem_name}")
        end
        raise "bundle lock exited with status #{$?.exitstatus}" unless success
      rescue => e
        File.write(lockfile_path, before_contents)
        errors[gem_name] = e.message
        next
      end

      remaining_for_gem = DependencyAuditing.findings([lockfile_path], database: database, ignore: ignore)
        .select { |f| f.gem == gem_name }
      File.write(lockfile_path, before_contents) unless remaining_for_gem.empty?
    end

    remaining = DependencyAuditing.findings([lockfile_path], database: database, ignore: ignore)
    error_message = errors.empty? ? nil : errors.values.join('; ')

    if remaining.empty? && errors.empty?
      {lockfile: lockfile_path, status: RESOLVED, remaining_findings: []}
    elsif remaining.empty?
      {lockfile: lockfile_path, status: RESOLVED, remaining_findings: [], error_message: error_message}
    elsif errors.size == gems.size
      {lockfile: lockfile_path, status: ERROR, remaining_findings: [], error_message: error_message}
    else
      {lockfile: lockfile_path, status: UNRESOLVED, remaining_findings: remaining, error_message: error_message}
    end
  end
end
