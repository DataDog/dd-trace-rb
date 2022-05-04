# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

Gem::Specification.new do |spec|
  spec.name                  = 'ddtrace'
  spec.version               = DDTrace::VERSION::STRING
  spec.required_ruby_version = [">= #{DDTrace::VERSION::MINIMUM_RUBY_VERSION}", "< #{DDTrace::VERSION::MAXIMUM_RUBY_VERSION}"]
  spec.required_rubygems_version = '>= 2.0.0'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Datadog tracing code for your Ruby applications'
  spec.description = <<-EOS.gsub(/^[\s]+/, '')
    ddtrace is Datadog’s tracing client for Ruby. It is used to trace requests
    as they flow across web servers, databases and microservices so that developers
    have great visiblity into bottlenecks and troublesome requests.
  EOS

  spec.homepage = 'https://github.com/DataDog/dd-trace-rb'
  spec.license  = 'BSD-3-Clause'

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  else
    raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.'
  end

  spec.files =
    `git ls-files -z`
    .split("\x0")
    .reject { |f| f.match(%r{^(test|spec|features|[.]circleci|[.]github|[.]dd-ci|benchmarks|gemfiles|integration|tasks|sorbet|yard)/}) }
    .reject do |f|
      ['.dockerignore', '.env', '.gitattributes', '.gitlab-ci.yml', '.rspec', '.rubocop.yml',
       '.rubocop_todo.yml', '.simplecov', 'Appraisals', 'Gemfile', 'Rakefile', 'docker-compose.yml', '.pryrc', '.yardopts'].include?(f)
    end
  spec.executables   = ['ddtracerb']
  spec.require_paths = ['lib']

  if RUBY_VERSION >= '2.2.0'
    spec.add_dependency 'msgpack'
  else
    # msgpack 1.4 fails for Ruby 2.1: https://github.com/msgpack/msgpack-ruby/issues/205
    spec.add_dependency 'msgpack', '< 1.4'
  end

  # Used by the profiler native extension to support older Rubies (see NativeExtensionDesign.md for notes)
  #
  # Because we only use this for older Rubies, and we consider it "feature-complete" for those older Rubies,
  # we're pinning it at the latest available version and will manually bump the dependency as needed.
  spec.add_dependency 'debase-ruby_core_source', '<= 0.10.15'

  # Used by appsec
  spec.add_dependency 'libddwaf', '~> 1.3.0.1.0.a'

  spec.extensions = ['ext/ddtrace_profiling_native_extension/extconf.rb']
end
