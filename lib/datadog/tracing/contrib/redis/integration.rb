# typed: false
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/redis/configuration/settings'
require 'datadog/tracing/contrib/redis/patcher'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Description of Redis integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('3.2')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :redis, auto_patch: true

          def self.version
            Gem.loaded_specs['redis'] && Gem.loaded_specs['redis'].version
          end

          def self.loaded?
            !defined?(::Redis).nil?
          end

          def self.compatible?
            super && version >= MINIMUM_VERSION
          end

          def new_configuration
            Configuration::Settings.new
          end

          def patcher
            Patcher
          end

          def resolver
            @resolver ||= Configuration::Resolver.new
          end
        end
      end
    end
  end
end
