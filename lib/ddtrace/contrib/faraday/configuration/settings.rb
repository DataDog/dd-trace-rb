require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/faraday/ext'

module Datadog
  module Contrib
    module Faraday
      module Configuration
        # Custom settings for the Faraday integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_ERROR_HANDLER = lambda do |env|
            Datadog::Ext::HTTP::ERROR_RANGE.cover?(env[:status])
          end

          option :distributed_tracing, default: true
          option :error_handler, default: DEFAULT_ERROR_HANDLER
          option :service_name, default: Ext::SERVICE_NAME
          option :split_by_domain, default: false
        end
      end
    end
  end
end
