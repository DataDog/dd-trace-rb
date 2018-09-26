require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/elasticsearch/ext'

module Datadog
  module Contrib
    module Elasticsearch
      module Configuration
        # Custom settings for the Elasticsearch integration
        class Settings < Contrib::Configuration::Settings
          option :quantize, default: {}
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
