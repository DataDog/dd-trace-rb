require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/rest_client/configuration/settings'
require 'ddtrace/contrib/rest_client/patcher'

module Datadog
  module Contrib
    module RestClient
      # Description of RestClient integration
      class Integration
        include Contrib::Integration
        register_as :rest_client

        def self.compatible?
          RUBY_VERSION >= '1.9.3' && defined?(::RestClient::Request)
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
