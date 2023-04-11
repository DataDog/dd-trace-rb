# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack integration constants
        module Ext
          APP = 'rack'
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED' # TODO: DD_APPSEC?
        end
      end
    end
  end
end
