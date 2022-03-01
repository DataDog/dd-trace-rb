# typed: false

require 'datadog/tracing/contrib/configuration/resolvers/pattern_resolver'
require 'datadog/tracing/contrib/http/circuit_breaker'
require 'datadog/tracing/contrib/http/configuration/settings'
require 'datadog/tracing/contrib/http/patcher'
require 'datadog/tracing/contrib/integration'
require 'ddtrace/version'

module Datadog
  module Tracing
    module Contrib
      # HTTP integration
      module HTTP
        extend CircuitBreaker

        # Description of HTTP integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = DDTrace::VERSION::MINIMUM_RUBY_VERSION

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :http, auto_patch: true

          def self.version
            Gem::Version.new(RUBY_VERSION)
          end

          def self.loaded?
            !defined?(::Net::HTTP).nil?
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end

          def resolver
            @resolver ||= Contrib::Configuration::Resolvers::PatternResolver.new
          end
        end
      end
    end
  end
end
