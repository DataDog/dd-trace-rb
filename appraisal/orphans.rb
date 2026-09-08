# Finds gemfiles with no matching `appraise` definition. `dependency:generate`
# never deletes a gemfile, so one can outlive its definition silently.
#
# Usage: `bundle exec rake dependency:orphans` (or `bundle exec ruby appraisal/orphans.rb` directly)

require_relative '../tasks/appraisal_conversion'
require_relative 'coverage_matrix_helper'

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
exit if orphans.empty?

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

exit 1
