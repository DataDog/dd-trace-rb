source 'https://rubygems.org'

gemspec

gem 'appraisal', '~> 2.4.0'
gem 'benchmark-ips', '~> 2.8'
gem 'benchmark-memory', '< 0.2' # V0.2 only works with 2.5+
gem 'builder'
gem 'climate_control', '~> 0.2.0'

gem 'concurrent-ruby'
gem 'extlz4', '~> 0.3', '>= 0.3.3' if RUBY_PLATFORM != 'java' # Used to test lz4 compression done by libdatadog
gem 'json-schema', '< 3' # V3 only works with 2.5+
gem 'memory_profiler', '~> 0.9'

gem 'os', '~> 1.1'
gem 'pimpmychangelog', '>= 0.1.2'
gem 'pry'
if RUBY_PLATFORM != 'java'
  # There's a few incompatibilities between pry/pry-byebug on older Rubies
  # There's also a few temproary incompatibilities with newer rubies
  gem 'pry-byebug' if RUBY_VERSION >= '2.6.0' && RUBY_ENGINE != 'truffleruby' && RUBY_VERSION < '3.2.0'
  gem 'pry-nav' if RUBY_VERSION < '2.6.0'
  gem 'pry-stack_explorer'
else
  gem 'pry-debugger-jruby'
end
gem 'rake', '>= 10.5'
gem 'rake-compiler', '~> 1.1', '>= 1.1.1' # To compile native extensions
gem 'rspec', '~> 3.12'
gem 'rspec-collection_matchers', '~> 1.1'
gem 'rspec-wait', '~> 0'

gem 'rspec_junit_formatter', '>= 0.5.1'

gem 'simplecov', '~> 0.22'
gem 'simplecov-cobertura', '~> 2.1.0' # Used by codecov

gem 'warning', '~> 1' # NOTE: Used in spec_helper.rb
gem 'webmock', '>= 3.10.0'

gem 'rexml', '>= 3.2.7' # https://www.ruby-lang.org/en/news/2024/05/16/dos-rexml-cve-2024-35176/

gem 'webrick', '>= 1.7.0' if RUBY_VERSION >= '3.0.0' # No longer bundled by default since Ruby 3.0

gem 'yard', '~> 0.9' # NOTE: YardDoc is generated with ruby 3.2 in GitHub Actions

if RUBY_VERSION >= '2.6.0'
  # 1.50 is the last version to support Ruby 2.6
  gem 'rubocop', '~> 1.50.0', require: false
  gem 'rubocop-packaging', '~> 0.5.2', require: false
  gem 'rubocop-performance', '~> 1.9', require: false
  # 2.20 is the last version to support Ruby 2.6
  gem 'rubocop-rspec', ['~> 2.20', '< 2.21'], require: false
end

# Optional extensions
# TODO: Move this to Appraisals?
# dogstatsd v5, but lower than 5.2, has possible memory leak with datadog.
# @see https://github.com/DataDog/dogstatsd-ruby/issues/182
gem 'dogstatsd-ruby', '>= 3.3.0', '!= 5.0.0', '!= 5.0.1', '!= 5.1.0'

# Profiler testing dependencies
# NOTE: We're excluding versions 3.7.0 and 3.7.1 for the reasons documented in #1424.
#       Since most of our customers won't have BUNDLE_FORCE_RUBY_PLATFORM=true, it's not something we want to add
#       to our CI, so we just shortcut and exclude specific versions that were affecting our CI.
if RUBY_PLATFORM != 'java'
  if RUBY_VERSION >= '2.7.0' # Bundler 1.x fails to find that versions >= 3.8.0 are not compatible because of binary gems
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1']
  elsif RUBY_VERSION >= '2.3.0'
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1', '< 3.19.2']
  else
    gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1', '< 3.8.0']
  end
end

group :check do
  if RUBY_VERSION >= '3.0.0' && RUBY_PLATFORM != 'java'
    gem 'rbs', '~> 3.2.0', require: false
    gem 'steep', '~> 1.6.0', require: false
  end
end

# `1.17.0` provides broken RBS type definitions
# https://github.com/ffi/ffi/blob/master/CHANGELOG.md#1170rc1--2024-04-08
#
# TODO: Remove this once the issue is resolved: https://github.com/ffi/ffi/issues/1107
gem 'ffi', '~> 1.16.3', require: false
