module Datadog
  module Core
    module Telemetry
      module Schemas
        module Base
          module V1
            # Describes attributes for host object
            class Host
              attr_reader :container_id, :hostname, :kernel_name, :kernel_release, :kernel_version, :os, :os_version

              def initialize(container_id = nil, hostname = nil, kernel_name = nil, kernel_release = nil,
                             kernel_version = nil, os = nil, os_version = nil)
                @container_id = container_id
                @hostname = hostname
                @kernel_name = kernel_name
                @kernel_release = kernel_release
                @kernel_version = kernel_version
                @os = os
                @os_version = os_version
              end
            end
          end
        end
      end
    end
  end
end
