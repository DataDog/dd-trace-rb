# Builds a matrix of versions to test for a given integration.
#
# Shared between `appraisal/generate.rb` (which defines a real `appraise`/`gem`
# backed by `Appraisal::Appraisal`) and `tasks/appraisal_verify.rb` (which
# defines lightweight stubs that only record names), so both operate on the
# same integration -> appraisal-name mapping.
#
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
