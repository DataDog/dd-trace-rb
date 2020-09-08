require 'ddtrace/ext/runtime'
require 'ddtrace/runtime/cgroup'

module Datadog
  module Runtime
    # For container environments
    module Container
      UUID_PATTERN = '[0-9a-f]{8}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{12}'.freeze
      CONTAINER_PATTERN = '[0-9a-f]{64}'.freeze

      POD_REGEX = /(pod)?(#{UUID_PATTERN})(?:.slice)?$/
      CONTAINER_REGEX = /(#{UUID_PATTERN}|#{CONTAINER_PATTERN})(?:.scope)?$/

      Descriptor = Struct.new(
        :platform,
        :container_id,
        :task_uid
      )

      module_function

      def platform
        descriptor.platform
      end

      def container_id
        descriptor.container_id
      end

      def task_uid
        descriptor.task_uid
      end

      def descriptor
        @descriptor ||= begin
          Descriptor.new.tap do |descriptor|
            begin
              Cgroup.descriptors.each do |cgroup_descriptor|
                # Parse container data from cgroup descriptor
                path = cgroup_descriptor.path
                next if path.nil?

                # Split path into parts
                parts = path.split('/')
                parts.shift # Remove leading empty part
                next if parts.length < 2

                # Read info from path
                platform = parts[0]
                container_id = parts[-1][CONTAINER_REGEX]
                task_uid = parts[-2][POD_REGEX]

                # If container ID wasn't found, ignore.
                # Path might describe a non-container environment.
                next if container_id.nil?

                descriptor.platform = platform
                descriptor.container_id = container_id
                descriptor.task_uid = task_uid

                break
              end
            rescue StandardError => e
              Datadog.logger.error(
                "Error while parsing container info. Cause: #{e.message} Location: #{e.backtrace.first}"
              )
            end
          end
        end
      end
    end
  end
end
