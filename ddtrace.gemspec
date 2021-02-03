# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

Gem::Specification.new do |spec|
  spec.name                  = 'ddtrace'
  spec.version               = Datadog::VERSION::STRING
  spec.required_ruby_version = ">= #{Datadog::VERSION::MINIMUM_RUBY_VERSION}"
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

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = ['ddtracerb']
  spec.require_paths = ['lib']

  if RUBY_VERSION >= '2.2.0'
    spec.add_dependency 'msgpack'
  else
    # msgpack 1.4 fails for Ruby 2.0 and 2.1: https://github.com/msgpack/msgpack-ruby/issues/205
    spec.add_dependency 'msgpack', '< 1.4'
  end

  # Support correct forwarding of arguments for both Ruby <= 2.6 and Ruby >= 3, see
  # https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/#a-compatible-delegation
  spec.add_dependency 'ruby2_keywords'

  # Optional extensions
  spec.add_development_dependency 'ffi', '~> 1.0'

  if RUBY_PLATFORM != 'java'
    # NOTE: Exclude 3.7.x because the required_ruby_version mismatches
    #       actual Ruby support. It would break Ruby < 2.3.
    google_protobuf_versions = [
      '~> 3.0',
      '!= 3.7.0.rc.2',
      '!= 3.7.0.rc.3',
      '!= 3.7.0',
      '!= 3.7.1',
      '!= 3.8.0.rc.1'
    ]

    spec.add_development_dependency 'google-protobuf', *google_protobuf_versions
  end
end
