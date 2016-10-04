# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ddtrace/version'

Gem::Specification.new do |spec|
  spec.name                  = "ddtrace"
  spec.version               = Datadog::VERSION::STRING
  # TODO[manu]: we should run our tests with previous ruby versions
  spec.required_ruby_version = '>= 2.1.0'
  spec.authors               = ["Datadog, Inc."]
  spec.email                 = ["dev@datadoghq.com"]

  spec.summary     = "Datadog tracing code for your Ruby applications"
  spec.description = <<-EOS
ddtrace is Datadog’s tracing client for Ruby. It is used to trace requests
as they flow across web servers, databases and microservices so that developers
have great visiblity into bottlenecks and troublesome requests.
EOS

  spec.homepage = "https://github.com/DataDog/dd-trace-rb"
  spec.license  = "MIT"

  # TODO[manu]: after GA, change that with rubygems.org
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "http://localhost:8808"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
