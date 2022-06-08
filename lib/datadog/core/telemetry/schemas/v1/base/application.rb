module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for application environment object
            class Application
              attr_reader \
                :env,
                :language_name,
                :language_version,
                :products,
                :runtime_name,
                :runtime_patches,
                :runtime_version,
                :service_name,
                :service_version,
                :tracer_version

              def initialize(language_name:, language_version:, service_name:, tracer_version:, env: nil, products: nil,
                             runtime_name: nil, runtime_patches: nil, runtime_version: nil, service_version: nil)
                @env = env
                @language_name = language_name
                @language_version = language_version
                @products = products
                @runtime_name = runtime_name
                @runtime_patches = runtime_patches
                @runtime_version = runtime_version
                @service_name = service_name
                @service_version = service_version
                @tracer_version = tracer_version
              end
            end
          end
        end
      end
    end
  end
end
