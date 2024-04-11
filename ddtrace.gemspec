# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

Gem::Specification.new do |spec|
  spec.name                  = 'ddtrace'
  spec.version               = DDTrace::VERSION::STRING
  # required_ruby_version should be in a single line due to test-head workflow `sed` to unlock the version
  spec.required_ruby_version = [">= #{DDTrace::VERSION::MINIMUM_RUBY_VERSION}", "< #{DDTrace::VERSION::MAXIMUM_RUBY_VERSION}"]
  spec.required_rubygems_version = '>= 2.0.0'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Datadog tracing code for your Ruby applications'
  spec.description = <<-DESC.gsub(/^\s+/, '')
    ddtrace is Datadog's tracing client for Ruby. It is used to trace requests
    as they flow across web servers, databases and microservices so that developers
    have great visiblity into bottlenecks and troublesome requests.
  DESC

  spec.homepage = 'https://github.com/DataDog/dd-trace-rb'
  spec.license  = 'BSD-3-Clause'

  if spec.respond_to?(:metadata)
    # spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    # For testing purposes, using a local gemstash instead of rubygems.org
    spec.metadata['allowed_push_host'] = 'http://localhost:9292/private'
    spec.metadata['changelog_uri'] = 'https://github.com/DataDog/dd-trace-rb/blob/master/CHANGELOG.md'
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  # ddtace 2.0 is a shim to the renamed `datadog` gem
  spec.files = [
    'lib/ddtrace/version.rb',         # Should the version file be included ?
    'lib/ddtrace/auto_instrument.rb', # To support auto-instrumentation in Gemfile
  ]

  # For testing purposes, fixing with a prerelease version
  spec.add_runtime_dependency 'datadog', '= 2.0.0.beta1'

  spec.post_install_message = <<-MSG
    Thank you for installing ddtrace 2.0! 🎉

    In 2.0, we've renamed the gem to `datadog` to better reflect the full suite of Datadog's products.

    Instead of requiring `ddtrace`, you should now require `datadog` in your Gemfile.
  MSG
end
