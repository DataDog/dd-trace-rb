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

require "appraisal/appraisal"

require_relative "../tasks/appraisal_conversion"

gemfile = Appraisal::Gemfile.new.tap do |g|
  # Support `eval_gemfile` for `Bundler::DSL`
  g.define_singleton_method(:eval_gemfile) {|file| load(file) }
  g.load(ENV["BUNDLE_GEMFILE"] || "Gemfile")
end

appraisals = []

REMOVED_GEMS = {
  :check => [
    'rbs',
    'steep',
    'standard',
  ],
  :dev => [
    'ruby-lsp',
  ],
}

define_singleton_method(:appraise) do |name, &block|
  # Customize name
  name = "#{AppraisalConversion.runtime_identifier}_#{name}"
  appraisal = Appraisal::Appraisal.new(name, gemfile)
  appraisal.instance_eval(&block)
  # Customize callback for removal
  REMOVED_GEMS.each do |group_name, gems|
    appraisal.group(group_name) do
      gems.each { |gem_name| remove_gem gem_name }
    end
  end
  appraisals << appraisal
end

# Builds a matrix of versions to test for a given integration

# `range`: the range of versions to test
# `gem`  : optional, gem name to test (gem name can be different from the integration name)
# `min`  : optional, minimum version to test
# `meta` : optional, additional metadata (development dependencies, etc.) for the group
def build_coverage_matrix(integration, range, gem: nil, min: nil, meta: {})
  gem ||= integration

  if min
    appraise "#{integration}-min" do
      gem gem, "= #{min}"
      meta.each { |k, v| v ? gem(k, v) : gem(k) }
    end
  end

  range.each do |n|
    appraise "#{integration}-#{n}" do
      gem gem, "~> #{n}"
      meta.each { |k, v| v ? gem(k, v) : gem(k) }
    end
  end

  appraise "#{integration}-latest" do
    # The latest group declares dependencies without version constraints,
    # still requires being updated to pick up the next major version and
    # committing the changes to lockfiles.
    gem gem
    meta.each { |k, v| v ? gem(k, v) : gem(k) }
  end
end

load(AppraisalConversion.definition)

puts appraisals.map(&:name)

appraisals.each(&:write_gemfile)
