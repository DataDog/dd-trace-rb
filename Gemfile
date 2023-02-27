source 'https://rubygems.org'

gemspec

# Development dependencies
gem 'addressable', '~> 2.4.0' # locking transitive dependency of webmock
if RUBY_VERSION < '2.3'
  gem 'appraisal', '~> 2.2.0'
else
  gem 'appraisal', '~> 2.4.0'
end
gem 'benchmark-ips', '~> 2.8'
gem 'benchmark-memory', '< 0.2' # V0.2 only works with 2.5+
gem 'builder'
gem 'climate_control', '~> 0.2.0'
# Leave it open as we also have it as an integration and want Appraisal to control the version under test.
if RUBY_VERSION >= '2.2.0'
  gem 'concurrent-ruby'
else
  gem 'concurrent-ruby', '< 1.1.10'
end
gem 'extlz4', '~> 0.3', '>= 0.3.3' if RUBY_PLATFORM != 'java' # Used to test lz4 compression done by libdatadog
gem 'json', '< 2.6' if RUBY_VERSION < '2.3.0'
gem 'json-schema', '< 3' # V3 only works with 2.5+
if RUBY_VERSION >= '2.3.0'
  gem 'memory_profiler', '~> 0.9'
else
  gem 'memory_profiler', '= 0.9.12'
end

gem 'os', '~> 1.1'
gem 'pimpmychangelog', '>= 0.1.2'
gem 'pry'
if RUBY_PLATFORM != 'java'
  # There's a few incompatibilities between pry/pry-byebug on older Rubies
  # There's also a few temproary incompatibilities with newer rubies
  gem 'pry-byebug' if RUBY_VERSION >= '2.6.0' && RUBY_ENGINE != 'truffleruby' && RUBY_VERSION < '3.2.0'
  gem 'pry-nav' if RUBY_VERSION < '2.6.0'
  gem 'pry-stack_explorer' if RUBY_VERSION >= '2.5.0'
else
  gem 'pry-debugger-jruby'
end
if RUBY_VERSION >= '2.2.0'
  gem 'rake', '>= 10.5'
else
  gem 'rake', '~> 12.3'
end
gem 'rake-compiler', '~> 1.1', '>= 1.1.1' # To compile native extensions
gem 'redcarpet', '~> 3.4' if RUBY_PLATFORM != 'java'
gem 'rspec', '~> 3.12'
gem 'rspec-collection_matchers', '~> 1.1'
gem 'rspec-wait', '~> 0'
if RUBY_VERSION >= '2.3.0'
  gem 'rspec_junit_formatter', '>= 0.5.1'
else
  # Newer versions do not support Ruby < 2.3.
  gem 'rspec_junit_formatter', '<= 0.4.1'
end
gem 'rspec_n', '~> 1.3' if RUBY_VERSION >= '2.4.0'
gem 'ruby-prof', '~> 1.4' if RUBY_PLATFORM != 'java' && RUBY_VERSION >= '2.4.0'
if RUBY_VERSION >= '2.5.0'
  # Merging branch coverage results does not work for old, unsupported rubies.
  # We have a fix up for review, https://github.com/simplecov-ruby/simplecov/pull/972,
  # but given it only affects unsupported version of Ruby, it might not get merged.
  gem 'simplecov', git: 'https://github.com/DataDog/simplecov', ref: '3bb6b7ee58bf4b1954ca205f50dd44d6f41c57db'
  gem 'simplecov-cobertura', '~> 2.1.0' # Used by codecov
else
  # Compatible with older rubies. This version still produces compatible output
  # with a newer version when the reports are merged.
  gem 'simplecov', '~> 0.17'
end
gem 'simplecov-html', '~> 0.10.2' if RUBY_VERSION < '2.4.0'
gem 'warning', '~> 1' if RUBY_VERSION >= '2.5.0'
gem 'webmock', '>= 3.10.0'
if RUBY_VERSION < '2.3.0'
  gem 'rexml', '< 3.2.5' # Pinned due to https://github.com/ruby/rexml/issues/69
end
gem 'webrick', '>= 1.7.0' if RUBY_VERSION >= '3.0.0' # No longer bundled by default since Ruby 3.0
if RUBY_VERSION >= '2.3.0'
  gem 'yard', '~> 0.9'
else
  gem 'yard', ['~> 0.9', '< 0.9.27'] # yard 0.9.27 starts pulling webrick as a gem dependency
end

if RUBY_VERSION >= '2.4.0'
  gem 'rubocop', ['~> 1.10', '< 1.33.0'], require: false
  gem 'rubocop-packaging', '~> 0.5', require: false
  gem 'rubocop-performance', '~> 1.9', require: false
  gem 'rubocop-rspec', '~> 2.2', require: false
end

# Optional extensions
# TODO: Move this to Appraisals?
# dogstatsd v5, but lower than 5.2, has possible memory leak with ddtrace.
# @see https://github.com/DataDog/dogstatsd-ruby/issues/182
gem 'dogstatsd-ruby', '>= 3.3.0', '!= 5.0.0', '!= 5.0.1', '!= 5.1.0'
gem 'opentracing', '>= 0.4.1'

# Profiler optional dependencies
# NOTE: We're excluding versions 3.7.0 and 3.7.1 for the reasons documented in #1424 and the big comment in
#       lib/datadog/profiling.rb: it breaks for some older rubies in CI without BUNDLE_FORCE_RUBY_PLATFORM=true.
#       Since most of our customers won't have BUNDLE_FORCE_RUBY_PLATFORM=true, it's not something we want to add
#       to our CI, so we just shortcut and exclude specific versions that were affecting our CI.
if RUBY_PLATFORM != 'java'
  if RUBY_VERSION >= '2.5.0' # Bundler 1.x fails to find that versions >= 3.8.0 are not compatible because of binary gems
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1']
  elsif RUBY_VERSION >= '2.3.0'
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1', '< 3.19.2']
  else
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1', '< 3.8.0']
  end
end

group :check do
  if RUBY_VERSION >= '2.6.0' && RUBY_PLATFORM != 'java'
    gem 'rbs', '~> 2.8.1', require: false
    gem 'steep', '~> 1.3.0', require: false
  end
end

gem 'docile', '~> 1.3.5' if RUBY_VERSION < '2.5'
gem 'ffi', '~> 1.12.2' if RUBY_VERSION < '2.3'
gem 'msgpack', '~> 1.3.3' if RUBY_VERSION < '2.4'
