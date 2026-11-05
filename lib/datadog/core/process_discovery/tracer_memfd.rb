# frozen_string_literal: true

module Datadog
  module Core
    module ProcessDiscovery
      class TracerMemfd
        def shutdown!(logger)
          ProcessDiscovery._native_close_tracer_memfd(self, logger)
        end
      end
    end
  end
end
