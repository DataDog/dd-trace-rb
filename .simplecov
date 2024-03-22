# Enable branch coverage reporting.
# SimpleCov only supports branch coverage in
# Ruby >= 2.5.
SimpleCov.enable_coverage :branch if RUBY_VERSION >= '2.5.0'

# Categorize SimpleCov report, for easier reading
SimpleCov.add_group 'contrib', '/lib/datadog/tracing/contrib'
SimpleCov.add_group 'transport', '/lib/datadog/core/transport'
SimpleCov.add_group 'spec', '/spec/'

# Exclude code not maintained by this project
SimpleCov.add_filter %r{/vendor/}

SimpleCov.coverage_dir ENV.fetch('COVERAGE_DIR', 'coverage')

# Each test run requires its own unique command_name.
# When running `rake spec:test_name`, the test process doesn't have access to the
# rake task process, so we have come up with unique values ourselves.
#
# The current approach is to combine the ruby engine (ruby-2.7,jruby-9.2),
# program name (rspec/test), command line arguments (--pattern spec/**/*_spec.rb),
# and the loaded gemset.
#
# This should allow us to distinguish between runs with the same tests, but different gemsets:
#   * appraisal rails5-mysql2 rake spec:rails
#   * appraisal rails5-postgres rake spec:rails
#
# Subsequent runs of the same exact test suite should have the same command_name.
command_line_arguments = ARGV.join(' ')
gemset_hash = Digest::MD5.hexdigest Gem.loaded_specs.values.map { |x| "#{x.name}#{x.version}" }.sort.join
ruby_engine = if defined?(RUBY_ENGINE_VERSION)
  "#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}"
else
  "#{RUBY_ENGINE}-#{RUBY_VERSION}" # For Ruby < 2.3
end
SimpleCov.command_name "#{ruby_engine}:#{gemset_hash}:#{$PROGRAM_NAME} #{command_line_arguments}"

# A very large number to disable result merging timeout
SimpleCov.merge_timeout 2 ** 31

# DEV If we choose to enforce a hard minimum.
# SimpleCov.minimum_coverage 95

# DEV If we choose to enforce a maximum coverage drop.
# DEV We have to figure out where to store previous coverage data
# DEV in order to perform this comparison
# SimpleCov.maximum_coverage_drop 1
