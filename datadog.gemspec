# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
# DEV: Loading gem files here is undesirable because it pollutes the application namespace.
# DEV: In this case, `bundle exec ruby -e 'puts defined?(Datadog)'` will return `constant`
# DEV: even though `require 'datadog'` wasn't executed. But only the version file was loaded.
# DEV: We should avoid loading gem files to fetch the version here.
require 'datadog/version'

Gem::Specification.new do |spec|
  spec.name                  = 'datadog'
  spec.version               = Datadog::VERSION::STRING
  # required_ruby_version should be in a single line due to test-head workflow `sed` to unlock the version
  spec.required_ruby_version = [">= #{Datadog::VERSION::MINIMUM_RUBY_VERSION}", "< #{Datadog::VERSION::MAXIMUM_RUBY_VERSION}"] # rubocop:disable Layout/LineLength
  spec.required_rubygems_version = '>= 2.0.0'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Datadog tracing code for your Ruby applications'
  spec.description = <<-DESC.gsub(/^\s+/, '')
    datadog is Datadog's client library for Ruby. It includes a suite of tools
    which provide visibility into the performance and security of Ruby applications,
    to enable Ruby developers to identify bottlenecks and other issues.
  DESC

  spec.homepage = 'https://github.com/DataDog/dd-trace-rb'
  spec.licenses = ['BSD-3-Clause', 'Apache-2.0']

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    spec.metadata['changelog_uri'] = "https://github.com/DataDog/dd-trace-rb/blob/v#{spec.version}/CHANGELOG.md"
    spec.metadata['source_code_uri'] = "https://github.com/DataDog/dd-trace-rb/tree/v#{spec.version}"
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files =
    Dir[*%w[
      CHANGELOG.md
      LICENSE*
      NOTICE
      README.md
      bin/**/*
      ext/**/*
      lib/**/*
    ]]
      .select { |fn| File.file?(fn) } # We don't want directories, only files
      .reject { |fn| fn.end_with?('.so', '.bundle') } # Exclude local profiler binary artifacts
      .reject { |fn| fn.end_with?('skipped_reason.txt') } # Generated by profiler; should never be distributed

  spec.executables   = ['ddprofrb']
  spec.require_paths = ['lib']

  # Used to serialize traces to send them to the Datadog Agent.
  #
  # msgpack 1.4 fails for Ruby 2.1 (see https://github.com/msgpack/msgpack-ruby/issues/205)
  # so a restriction needs to be manually added for the `Gemfile`.
  #
  # We can't add a restriction here, since there's no way to add it only for older
  # rubies, see #1739 and #1336 for an extended discussion about this
  spec.add_dependency 'msgpack'

  # Used by the profiler native extension to support Ruby < 2.6 and > 3.2
  #
  # We decided to pin it at the latest available version and will manually bump the dependency as needed.
  spec.add_dependency 'datadog-ruby_core_source', '= 3.3.6'

  # Used by appsec
  spec.add_dependency 'libddwaf', '~> 1.14.0.0.0'

  # When updating the version here, please also update the version in `libdatadog_extconf_helpers.rb`
  # (and yes we have a test for it)
  spec.add_dependency 'libdatadog', '~> 13.1.0.1.0'

  spec.extensions = [
    'ext/datadog_profiling_native_extension/extconf.rb',
    'ext/datadog_profiling_loader/extconf.rb',
    'ext/libdatadog_api/extconf.rb'
  ]
end
