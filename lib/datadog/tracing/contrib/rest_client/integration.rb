# typed: false

require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/rest_client/configuration/settings'
require 'datadog/tracing/contrib/rest_client/patcher'

module Datadog
  module Tracing
    module Contrib
      module RestClient
        # Description of RestClient integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.8')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :rest_client

          def self.version
            Gem.loaded_specs['rest-client'] && Gem.loaded_specs['rest-client'].version
          end

          def self.loaded?
            !defined?(::RestClient::Request).nil?
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
