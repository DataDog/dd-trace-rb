require 'datadog/core/telemetry/schemas/utils/validation'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for host object
            class Host
              include Schemas::Utils::Validation

              ERROR_NIL_ARGUMENTS = 'At least one non-nil argument must be passed to Host'.freeze
              ERROR_BAD_CONTAINER_ID_MESSAGE = ':container_id must be of type String'.freeze
              ERROR_BAD_HOSTNAME_MESSAGE = ':hostname must be of type String'.freeze
              ERROR_BAD_KERNEL_NAME_MESSAGE = ':kernel_name must be of type String'.freeze
              ERROR_BAD_KERNEL_RELEASE_MESSAGE = ':kernel_release must be of type String'.freeze
              ERROR_BAD_KERNEL_VERSION_MESSAGE = ':kernel_version must be of type String'.freeze
              ERROR_BAD_OS_VERSION_MESSAGE = ':os_version must be of type String'.freeze
              ERROR_BAD_OS_MESSAGE = ':os must be of type String'.freeze

              attr_reader \
                :container_id,
                :hostname,
                :kernel_name,
                :kernel_release,
                :kernel_version,
                :os_version,
                :os

              def initialize(container_id: nil, hostname: nil, kernel_name: nil, kernel_release: nil, kernel_version: nil,
                             os_version: nil, os: nil)
                if container_id.nil? && hostname.nil? && kernel_name.nil? && kernel_release.nil? && kernel_version.nil? &&
                   os_version.nil? && os.nil?
                  raise ArgumentError, ERROR_NIL_ARGUMENTS
                end
                raise ArgumentError, ERROR_BAD_CONTAINER_ID_MESSAGE unless valid_optional_string?(container_id)
                raise ArgumentError, ERROR_BAD_HOSTNAME_MESSAGE unless valid_optional_string?(hostname)
                raise ArgumentError, ERROR_BAD_KERNEL_NAME_MESSAGE unless valid_optional_string?(kernel_name)
                raise ArgumentError, ERROR_BAD_KERNEL_RELEASE_MESSAGE unless valid_optional_string?(kernel_release)
                raise ArgumentError, ERROR_BAD_KERNEL_VERSION_MESSAGE unless valid_optional_string?(kernel_version)
                raise ArgumentError, ERROR_BAD_OS_VERSION_MESSAGE unless valid_optional_string?(os_version)
                raise ArgumentError, ERROR_BAD_OS_MESSAGE unless valid_optional_string?(os)

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
