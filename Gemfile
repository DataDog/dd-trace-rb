source 'https://rubygems.org'

gemspec

gem 'appraisal', '~> 2.2'
gem 'rake', '>= 10.5'
gem 'rake-compiler', '~> 1.1', '>= 1.1.1' # To compile native extensions

# Ignore warnings emitted by dependencies
gem 'warning', '~> 1' if RUBY_VERSION >= '2.5.0'

gem 'builder' # TODO ???

# Leave it open as we also have it as an integration and want Appraisal to control the version under test.
gem 'concurrent-ruby' # TODO do we need it here?

# TODO: Move this to Appraisals
# dogstatsd v5, but lower than 5.2, has possible memory leak with ddtrace.
# @see https://github.com/DataDog/dogstatsd-ruby/issues/182
gem 'dogstatsd-ruby', '>= 3.3.0', '!= 5.0.0', '!= 5.0.1', '!= 5.1.0'

# :test dependencies should not conflict with gems under test if possible.
group :test do
  gem 'climate_control', '~> 0.2.0' # Mocks environment variables
  gem 'os', '~> 1.1' # Used by PlatformHelpers

  begin # rspec
    gem 'rspec', '~> 3.12'
    gem 'rspec-collection_matchers', '~> 1.1'
    if RUBY_VERSION >= '2.3.0'
      gem 'rspec_junit_formatter', '>= 0.5.1'
    else
      # Newer versions do not support Ruby < 2.3.
      gem 'rspec_junit_formatter', '<= 0.4.1'
    end
  end

  begin # simplecov
    if RUBY_VERSION >= '2.5.0'
      # Merging branch coverage results does not work for old, unsupported rubies.
      # We have a fix up for review, https://github.com/simplecov-ruby/simplecov/pull/972,
      # but given it only affects unsupported version of Ruby, it might not get merged.
      gem 'simplecov', git: 'https://github.com/DataDog/simplecov', ref: '3bb6b7ee58bf4b1954ca205f50dd44d6f41c57db'
    else
      # Compatible with older rubies. This version still produces compatible output
      # with a newer version when the reports are merged.
      gem 'simplecov', '~> 0.17'
    end
  end

  begin # webmock
    gem 'webmock', '>= 3.10.0'
    gem 'addressable', '~> 2.4.0' # locking transitive dependency of webmock
  end

  gem 'webrick', '>= 1.7.0' if RUBY_VERSION >= '3.0.0' # No longer bundled by default since Ruby 3.0

  begin # Profiling
    gem 'extlz4', '~> 0.3', '>= 0.3.3' if RUBY_PLATFORM != 'java' # Used to test lz4 compression done by libdatadog
    gem 'json-schema', '< 3' # V3 only works with 2.5+

    # NOTE: We're excluding versions 3.7.0 and 3.7.1 for the reasons documented in #1424 and the big comment in
    #       lib/datadog/profiling.rb: it breaks for some older rubies in CI without BUNDLE_FORCE_RUBY_PLATFORM=true.
    #       Since most of our customers won't have BUNDLE_FORCE_RUBY_PLATFORM=true, it's not something we want to add
    #       to our CI, so we just shortcut and exclude specific versions that were affecting our CI.
    if RUBY_PLATFORM != 'java'
      if RUBY_VERSION >= '2.5.0' # Bundler 1.x fails to recognize that version >= 3.19.2 is not compatible with older rubies
        gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1']
      else
        gem 'google-protobuf', ['~> 3.0', '!= 3.7.0', '!= 3.7.1', '< 3.19.2']
      end
    end
  end
end

# Optional dependencies. These are not installed by default.

group :check, optional: true do
  if RUBY_VERSION >= '2.4.0'
    gem 'rubocop', ['~> 1.10', '< 1.33.0'], require: false
    gem 'rubocop-packaging', '~> 0.5', require: false
    gem 'rubocop-performance', '~> 1.9', require: false
    gem 'rubocop-rspec', '~> 2.2', require: false

    if RUBY_VERSION < '2.3.0'
      # Rubocop dependency, pinned due to https://github.com/ruby/rexml/issues/69
      gem 'rexml', '< 3.2.5' # TODO still needed?
    end
  end

  # For type checking
  # Sorbet releases almost daily, with new checks introduced that can make a
  # previously-passing codebase start failing. Thus, we need to lock to a specific
  # version and bump it from time to time.
  # Also, there's no support for windows
  if RUBY_VERSION >= '2.4.0' && (RUBY_PLATFORM =~ /^x86_64-(darwin|linux)/)
    gem 'sorbet', '= 0.5.9672'
    gem 'spoom', '~> 1.1'
  end
end

group :dev, optional: true do
  begin # pry
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
  end

  gem 'rspec_n', '~> 1.3' if RUBY_VERSION >= '2.4.0' # TODO Does anyone use this?
  gem 'ruby-prof', '~> 1.4' if RUBY_PLATFORM != 'java' && RUBY_VERSION >= '2.4.0'
end

group :benchmark, optional: true do
  gem 'benchmark-ips', '~> 2.8'
  gem 'benchmark-memory', '< 0.2' # V0.2 only works with 2.5+
  gem 'memory_profiler', '~> 0.9'
end

group :release, optional: true do
  gem 'pimpmychangelog', '>= 0.1.2' # Formats the CHANGELOG.md file
  gem 'redcarpet', '~> 3.4' if RUBY_PLATFORM != 'java' # Used by YARD to generate docs
  gem 'yard', '~> 0.9'
end
