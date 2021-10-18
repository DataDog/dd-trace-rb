module Datadog
  module Security
    module Contrib
      module Sinatra
        # Sinatra integration constants
        module Ext
          APP = 'sinatra'.freeze
          ENV_ENABLED = 'DD_TRACE_SINATRA_ENABLED'.freeze
        end
      end
    end
  end
end


