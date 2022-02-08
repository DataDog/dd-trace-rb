module Datadog
  module AppSec
    module Contrib
      module Rails
        # Rack integration constants
        module Ext
          APP = 'rails'.freeze
          ENV_ENABLED = 'DD_TRACE_RAILS_ENABLED'.freeze
        end
      end
    end
  end
end
