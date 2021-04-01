source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'addressable', '~> 2.4.0' # locking transitive dependency of webmock
gem 'appraisal', '~> 2.2'
gem 'benchmark-ips', '~> 2.8'
gem 'benchmark-memory', '~> 0.1'
gem 'builder'
gem 'climate_control', '~> 0.2.0'
# Leave it open as we also have it as an integration and want Appraisal to control the version under test.
gem 'concurrent-ruby'
gem 'memory_profiler', '~> 0.9'
gem 'minitest', '= 5.10.1'
gem 'minitest-around', '0.5.0'
gem 'minitest-stub_any_instance', '1.0.2'
gem 'pimpmychangelog', '>= 0.1.2'
gem 'pry'
if RUBY_PLATFORM != 'java'
  # There's a few incompatibilities between pry/pry-byebug on older Rubies
  gem 'pry-byebug' if RUBY_VERSION >= '2.6.0' && RUBY_ENGINE != 'truffleruby'
  gem 'pry-nav' if RUBY_VERSION < '2.6.0'
  gem 'pry-stack_explorer'
else
  gem 'pry-debugger-jruby'
end
gem 'rake', '>= 10.5'
gem 'redcarpet', '~> 3.4' if RUBY_PLATFORM != 'java'
gem 'rspec', '~> 3.10'
gem 'rspec-collection_matchers', '~> 1.1'
gem 'rspec_junit_formatter', '>= 0.4.1'
gem 'rspec_n', '~> 1.3' if RUBY_VERSION >= '2.3.0'
gem 'ruby-prof', '~> 1.4' if RUBY_PLATFORM != 'java' && RUBY_VERSION >= '2.4.0'
gem 'simplecov', '~> 0.17'
gem 'warning', '~> 1' if RUBY_VERSION >= '2.5.0'
gem 'webmock', '>= 3.10.0'
gem 'webrick', '>= 1.7.0' if RUBY_VERSION >= '3.0.0' # No longer bundled by default since Ruby 3.0
gem 'yard', '~> 0.9'

if RUBY_VERSION >= '2.4.0'
  gem 'rubocop', '~> 1.10', require: false
  gem 'rubocop-performance', '~> 1.9', require: false
  gem 'rubocop-rspec', '~> 2.2', require: false
end

# Optional extensions
# TODO: Move this to Appraisals?
gem 'dogstatsd-ruby', '>= 3.3.0'
gem 'opentracing', '>= 0.4.1'

# Profiler optional dependencies
# NOTE: We're excluding versions 3.7.0 and 3.7.1 for the reasons documented in #1424 and the big comment in
#       lib/ddtrace/profiling.rb: it breaks for some older rubies in CI without BUNDLE_FORCE_RUBY_PLATFORM=true.
#       Since most of our customers won't have BUNDLE_FORCE_RUBY_PLATFORM=true, it's not something we want to add
#       to our CI, so we just shortcut and exclude specific versions that were affecting our CI.
gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1'] if RUBY_PLATFORM != 'java'
