# Finds gemfiles with no matching `appraise` definition, and lockfiles with no
# matching gemfile. `dependency:generate` never deletes a gemfile, so one can
# outlive its definition silently; `dependency:lock` only rewrites lockfiles
# whose gemfiles exist, so a lockfile can outlive its gemfile the same way.
#
# Usage: `bundle exec rake dependency:orphans` (or `bundle exec ruby appraisal/orphans.rb` directly)

require_relative '../tasks/appraisal_conversion'
require_relative 'coverage_matrix_helper'
require_relative '../tasks/lockfile'

# Collect only the names `appraisal/#{runtime_identifier}.rb` would generate;
# skip building real `Appraisal::Appraisal`/`Bundler` objects since only the
# name matters here.
appraised_groups = []

define_singleton_method(:appraise) do |name, &block|
  appraised_groups << name
end

define_singleton_method(:gem) do |*_args|
  # no-op: `build_coverage_matrix` calls `gem` inside the `appraise` block,
  # but the check only needs the names `appraise` records above.
end

load(AppraisalConversion.definition)

runtime_prefix = "#{AppraisalConversion.runtime_identifier}_".tr('-', '_')
generated_gemfiles = Dir.glob(AppraisalConversion.gemfile_pattern).map { |path| File.basename(path, '.gemfile') }
defined_gemfiles = appraised_groups.map { |name| "#{runtime_prefix}#{name}".tr('-', '_') }

orphans = generated_gemfiles - defined_gemfiles
orphaned_lockfiles = Lockfile.orphaned_lockfile_paths(AppraisalConversion.gemfile_dir)

if orphans.any?
  matrix = eval(File.read('Matrixfile')).freeze # rubocop:disable Security/Eval
  ruby_column = AppraisalConversion.runtime_identifier.delete_prefix('ruby-')

  orphans.each do |gemfile|
    group = gemfile.delete_prefix(runtime_prefix)

    active = matrix.values.any? do |groups|
      coverage = groups.find { |matrix_group, _| matrix_group.tr('-', '_') == group }&.last
      coverage&.include?("✅ #{ruby_column}")
    end

    if active
      warn "#{gemfile}.gemfile has no `appraise '#{group}'` block in #{AppraisalConversion.definition}, " \
        "but Matrixfile marks it active for Ruby #{ruby_column}. Add the missing `appraise` block."
    else
      warn "#{gemfile}.gemfile has no `appraise '#{group}'` block in #{AppraisalConversion.definition}, " \
        "and Matrixfile does not mark it active for Ruby #{ruby_column}. Delete #{gemfile}.gemfile and its lockfile."
    end
  end
end

orphaned_lockfiles.each do |lockfile|
  warn "#{lockfile} has no corresponding #{lockfile.chomp('.lock')}; delete the lockfile."
end

exit 1 if orphans.any? || orphaned_lockfiles.any?
