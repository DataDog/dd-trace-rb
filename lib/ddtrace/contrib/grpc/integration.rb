require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/grpc/configuration/settings'
require 'ddtrace/contrib/grpc/patcher'

module Datadog
  module Contrib
    module GRPC
      # Description of gRPC integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.7.0')

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

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
