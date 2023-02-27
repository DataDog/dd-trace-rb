require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        # Description of gRPC integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.7.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :grpc, auto_patch: true

          def self.version
            Gem.loaded_specs['grpc'] && Gem.loaded_specs['grpc'].version
          end

          def self.loaded?
            !defined?(::GRPC).nil?
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
        end
      end
    end
  end
end
