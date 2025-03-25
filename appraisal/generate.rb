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
# For example, it solves the incompatbility of `eval_gemfile` from `Bundler::DSL`
#
# Usage: `bundle exec ruby appraisal/generate.rb`

require 'bundler'
require 'appraisal/appraisal'

require_relative '../tasks/appraisal_conversion'

gemfile = Appraisal::Gemfile.new.tap do |g|
  # Support `eval_gemfile` for `Bundler::DSL`
  g.define_singleton_method(:eval_gemfile) { |file| load(file) }
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

# Builds a matrix of versions to test for a given integration

# `range`: optional, the range of versions to test
# `gem`  : optional, gem name to test (gem name can be different from the integration name)
# `min`  : optional, minimum version to test
# `meta` : optional, additional metadata (development dependencies, etc.) for the group
#
# Examples:
#
# 1. Generating coverage starting minimal version
#
#    build_coverage_matrix('devise', min: '3.1.4')
#     ├─ appraise 'devise-min'
#     │   └─ gem 'devise', '= 3.1.4'
#     └─ appraise 'devise-latest'
#         └─ gem 'devise'
#
# 2. Generating coverage starting minimal version with some additional gems with
#    specific version tied to only minimal version
#
#    build_coverage_matrix('devise', min: '3.1.4', meta: { min: { 'bigdecimal' => '1.3.4' } })
#     ├─ appraise 'devise-min'
#     │   ├─ gem 'devise', '= 3.1.4'
#     │   └─ gem 'bigdecimal', '1.3.4'
#     └─ appraise 'devise-latest'
#         └─ gem 'devise'
#
# 3. Generating coverage starting minimal version with some additional gems with
#    specific version for all possible combinations
#
#    build_coverage_matrix('devise', min: '3.1.4', meta: { 'bigdecimal' => '3.0.0' })
#     ├─ appraise 'devise-min'
#     │   ├─ gem 'devise', '= 3.1.4'
#     │   └─ gem 'bigdecimal', '3.0.0'
#     └─ appraise 'devise-latest'
#         ├─ gem 'devise'
#         └─ gem 'bigdecimal', '3.0.0'
def build_coverage_matrix(integration, range = [], gem: nil, min: nil, meta: {})
  gem ||= integration

  meta_versions = meta.each_with_object({}) do |(key, value), memo|
    memo[key] = meta.delete(key) if value.is_a?(Hash)
  end

  if min
    appraise "#{integration}-min" do
      gem gem, "= #{min}"

      meta_versions[:min].to_h.merge(meta).each { |k, v| v ? gem(k, v) : gem(k) }
    end
  end

  range.each do |n|
    appraise "#{integration}-#{n}" do
      gem gem, "~> #{n}"
      meta_versions[n].to_h.merge(meta).each { |k, v| v ? gem(k, v) : gem(k) }
    end
  end

  appraise "#{integration}-latest" do
    # The latest group declares dependencies without version constraints,
    # still requires being updated to pick up the next major version and
    # committing the changes to lockfiles.
    gem gem
    meta_versions[:latest].to_h.merge(meta).each { |k, v| v ? gem(k, v) : gem(k) }
  end
end

load(AppraisalConversion.definition)

puts appraisals.map(&:name)

appraisals.each(&:write_gemfile)
