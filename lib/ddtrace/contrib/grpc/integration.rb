require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/grpc/configuration/settings'
require 'ddtrace/contrib/grpc/patcher'

module Datadog
  module Contrib
    module GRPC
      # Description of gRPC integration
      class Integration
        include Contrib::Integration

        register_as :grpc, auto_patch: true

        def self.version
          Gem.loaded_specs['grpc'] && Gem.loaded_specs['grpc'].version
        end

        def self.present?
          super && defined?(::GRPC)
        end

        def self.compatible?
          super \
            && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0') \
            && version >= Gem::Version.new('0.10.0')
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
