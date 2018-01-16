# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

Gem::Specification.new do |spec|
  spec.name                  = 'ddtrace'
  spec.version               = "#{Datadog::VERSION::STRING}#{ENV['VERSION_SUFFIX']}"
  spec.required_ruby_version = '>= 1.9.1'
  spec.authors               = ['Datadog, Inc.']
  spec.email                 = ['dev@datadoghq.com']

  spec.summary     = 'Datadog tracing code for your Ruby applications'
  spec.description = <<-EOS
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
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'msgpack'

  spec.add_development_dependency 'rake', '~> 10.5'
  spec.add_development_dependency 'rubocop', '= 0.49.1' if RUBY_VERSION >= '2.1.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-collection_matchers', '~> 1.1'
  spec.add_development_dependency 'minitest', '= 5.10.1'
  spec.add_development_dependency 'appraisal', '~> 2.2'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'webmock', '~> 2.0'
  spec.add_development_dependency 'builder'
  # locking transitive dependency of webmock
  spec.add_development_dependency 'addressable', '~> 2.4.0'
  spec.add_development_dependency 'redcarpet', '~> 3.4' if RUBY_PLATFORM != 'java'
  spec.add_development_dependency 'pry', '~> 0.10.4'
  spec.add_development_dependency 'pry-stack_explorer', '~> 0.4.9.2'
end
