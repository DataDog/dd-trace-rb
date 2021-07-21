module Datadog
  module Security
    module Contrib
      module Rack
        # Rack integration constants
        module Ext
          APP = 'rack'.freeze
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED'.freeze
        end
      end
    end
  end
end
