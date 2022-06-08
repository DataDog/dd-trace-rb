module Datadog
  module Core
    module Telemetry
      module Schemas
        module Base
          module V1
            # Describes attributes for application environment object
            class Application
              attr_reader :language_name, :language_version, :service_name, :tracer_version, :env, :runtime_name,
                          :runtime_patches, :runtime_version, :service_version, :products

              def initialize(language_name, language_version, service_name, tracer_version, env = nil, runtime_name = nil,
                             runtime_patches = nil, runtime_version = nil, service_version = nil, products = nil)
                @language_name = language_name
                @language_version = language_version
                @service_name = service_name
                @tracer_version = tracer_version
                @env = env
                @runtime_name = runtime_name
                @runtime_patches = runtime_patches
                @runtime_version = runtime_version
                @service_version = service_version
                @products = products
              end
            end
          end
        end
      end
    end
  end
end
