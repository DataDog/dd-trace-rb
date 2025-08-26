# frozen_string_literal: true

require_relative '../../api_security/endpoint_discovery/rails_routes_serializer'
require_relative '../../api_security/endpoint_discovery/sinatra_routes_serializer'
require_relative '../../api_security/endpoint_discovery/grape_routes_serializer'

module Datadog
  module AppSec
    module APISecurity
      module EndpointDiscovery
        # module that exports serialized endpoints via telemetry
        module TelemetryExporter
          module_function

          def export(serialized_routes)
            binding.irb
          end
        end
      end
    end
  end
end
