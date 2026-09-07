# Ruby script to replace `bundle exec appraisal generate`
#
# Why???
#
# 1. `Appraisals` file is extremely hard to extend, because the definition is evaluated by `instance_eval`
# 2. Not all `Bundler::DSL` methods are supported.
#
# This implementation provides a much easier interface to customize our needs,
# while still using the same Appraisal formatting.
#
# For example, it solves the incompatibility of `eval_gemfile` from `Bundler::DSL`
#
# Usage: `bundle exec ruby appraisal/generate.rb`

require 'bundler'
require 'appraisal/appraisal'

require_relative '../tasks/appraisal_conversion'
require_relative '../tasks/security_capabilities'
require_relative 'coverage_matrix_helper'
require_relative 'source_options'

gemfile = Appraisal::Gemfile.new.tap do |g|
  # Support `eval_gemfile` for `Bundler::DSL`
  g.define_singleton_method(:eval_gemfile) { |file| load(file) }

  if SecurityCapabilities.for_version(RUBY_VERSION)[:cooldown]
    g.define_singleton_method(:source) do |src, options = {}, &block|
      super(src, options.merge(cooldown: SecurityCapabilities::COOLDOWN_DAYS), &block)
    end
  end

  # The base gemfiles under `gemfiles/` declare `gemspec path: '..'` so Bundler
  # can resolve datadog.gemspec when those files are loaded directly via
  # `BUNDLE_GEMFILE`. Appraisal flattens all `eval_gemfile` content into a
  # single context, so the `..` would survive into integration gemfiles —
  # combined with Appraisal::Utils.prefix_path prepending another `..`, the
  # generated `gemspec path: "../.."` resolves outside the project. Normalize
  # to `.` so the generated value becomes `..`, relative to gemfiles/.
  g.define_singleton_method(:gemspec) do |options = {}|
    @gemspecs << Appraisal::Gemspec.new(options.merge(path: '.'))
  end

  g.load(Bundler.default_gemfile)
end

appraisals = []

definition = Bundler.definition
to_remove = Hash.new { |hash, key| hash[key] = definition.dependencies_for([key]).map(&:name) }

# Register groups to be removed
[:dev, :check].each { |g| to_remove[g] }

define_singleton_method(:appraise) do |name, &block|
  # Customize name
  name = "#{AppraisalConversion.runtime_identifier}_#{name}"
  appraisal = Appraisal::Appraisal.new(name, gemfile)
  appraisal.instance_eval(&block)

  # Customize callback for removal
  to_remove.each do |group_name, gems|
    appraisal.group(group_name) do
      gems.each { |gem_name| remove_gem gem_name }
    end
  end

  appraisals << appraisal
end

load(AppraisalConversion.definition)

puts appraisals.map(&:name)

appraisals.each(&:write_gemfile)
