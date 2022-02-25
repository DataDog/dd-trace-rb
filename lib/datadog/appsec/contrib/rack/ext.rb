module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack integration constants
        module Ext
          APP = 'rack'.freeze
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED'.freeze # TODO: DD_APPSEC?
        end
      end
    end
  end
end
