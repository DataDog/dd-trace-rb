# frozen_string_literal: true

require_relative 'cgroup'
require_relative 'ext'

module Datadog
  module Core
    module Environment
      # For container environments
      module Container
        UUID_PATTERN = '[0-9a-f]{8}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{4}[-_]?[0-9a-f]{12}'
        CONTAINER_PATTERN = '[0-9a-f]{64}'

        PLATFORM_REGEX = /(?<platform>.*?)(?:.slice)?$/.freeze
        POD_REGEX = /(?<pod>(pod)?#{UUID_PATTERN})(?:.slice)?$/.freeze
        CONTAINER_REGEX = /(?<container>#{UUID_PATTERN}|#{CONTAINER_PATTERN})(?:.scope)?$/.freeze
        FARGATE_14_CONTAINER_REGEX = /(?<container>[0-9a-f]{32}-[0-9]{1,10})/.freeze

        # From https://github.com/torvalds/linux/blob/5859a2b1991101d6b978f3feb5325dad39421f29/include/linux/proc_ns.h#L41-L49
        # Currently, the host namespace inode number is hardcoded.
        # We use it to determine if we're running in the host namespace.
        # This detection approach does not work when running in
        # ["Docker-in-Docker"](https://www.docker.com/resources/docker-in-docker-containerized-ci-workflows-dockercon-2023/).
        HOST_CGROUP_NAMESPACE_INODE = 0xEFFFFFFB

        Entry = Struct.new(
          :platform,
          :task_uid,
          :container_id,
          :inode
        )

        module_function

        # Returns HTTP headers representing container information.
        # These can used in any Datadog request that requires origin detection.
        # This is the recommended method to call to get container information.
        def to_headers
          headers = {}
          headers["Datadog-Container-ID"] = container_id if container_id
          headers["Datadog-Entity-ID"] = entity_id if entity_id
          headers["Datadog-External-Env"] = external_env if external_env
          headers
        end

        # Container ID, prefixed with "ci-" or Inode, prefixed with "in-".
        def entity_id
          if container_id
            "ci-#{container_id}"
          elsif inode
            "in-#{inode}"
          end
        end

        # External data supplied by the Datadog Cluster Agent Admission Controller.
        # @see {Ext::ENV_EXTERNAL_ENV} for more details.
        def external_env
          Datadog.configuration.container.external_env
        end

        # The container orchestration platform or runtime environment.
        #
        # Examples: Docker, Kubernetes, AWS Fargate, LXC, etc.
        #
        # @return [String, nil] The platform name (e.g., "docker", "kubepods", "fargate"), or nil if not containerized
        def platform
          entry.platform
        end

        # The unique identifier of the current container in the container environment.
        #
        # @return [String, nil] The container ID, or nil if not running in a containerized environment
        def container_id
          entry.container_id
        end

        # The unique identifier of the task or pod containing this container.
        #
        # In Kubernetes, this is the Pod UID; in AWS ECS/Fargate, the task ID.
        # Used to identify higher-level workloads beyond this container,
        # enabling correlation across container restarts and multi-container applications.
        #
        # @return [String, nil] The task/pod UID, or nil if not available in the current environment
        def task_uid
          entry.task_uid
        end

        # A unique identifier for the execution context (container or host namespace).
        #
        # Used as a fallback identifier when {#container_id} is unavailable.
        #
        # @return [Integer, nil] The namespace inode, or nil if unavailable
        def inode
          entry.inode
        end

        # Checks if the current process is running on the host cgroup namespace.
        # This indicates that the process is not running inside a container.
        # When unsure, we return `false` (not running on host).
        def running_on_host?
          return @running_on_host if defined?(@running_on_host)

          @running_on_host = begin
            if File.exist?('/proc/self/ns/cgroup')
              File.stat('/proc/self/ns/cgroup').ino == HOST_CGROUP_NAMESPACE_INODE
            else
              false
            end
          rescue => e
            Datadog.logger.debug(
              "Error while checking cgroup namespace. Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
            )
            false
          end
        end

        # All cgroup entries have the same container identity.
        # The first valid one is sufficient.
        # v2 entries are preferred over v1.
        def entry
          return @entry if defined?(@entry)

          # Scan all v2 entries first, only then falling back to v1 entries.
          #
          # To do this, we {Enumerable#partition} the list between v1 and v2,
          # with a `true` predicate for v2 entries, making v2 first
          # partition returned.
          #
          # All v2 entries have the `hierarchy` set to zero.
          # v1 entries have a non-zero `hierarchy`.
          entries = Cgroup.entries.partition { |d| d.hierarchy == '0' }.flatten(1)
          entries.each do |entry_obj|
            path = entry_obj.path
            next unless path

            # To ease handling, remove the emtpy leading "",
            # as `path` starts with a "/".
            parts = path.delete_prefix('/').split('/')

            # With not path information, we can still use the inode
            if parts.empty? && entry_obj.inode && !running_on_host?
              return @entry = Entry.new(nil, nil, nil, entry_obj.inode)
            end

            platform = parts[0][PLATFORM_REGEX, :platform]

            # Extract container_id and task_uid based on path structure
            container_id = task_uid = nil
            if parts.length >= 2
              # Try standard container regex first
              if (container_id = parts[-1][CONTAINER_REGEX, :container])
                # For 3+ parts, also extract task_uid
                if parts.length > 2
                  task_uid = parts[-2][POD_REGEX, :pod] || parts[1][POD_REGEX, :pod]
                end
              else
                # Fall back to Fargate regex
                container_id = parts[-1][FARGATE_14_CONTAINER_REGEX, :container]
              end
            end

            # container_id is a better container identifier than inode.
            # We MUST only populate one of them, to avoid container identification ambiguity.
            if container_id
              return @entry = Entry.new(platform, task_uid, container_id)
            elsif entry_obj.inode && !running_on_host?
              return @entry = Entry.new(platform, task_uid, nil, entry_obj.inode)
            end
          end

          @entry = Entry.new # Empty entry if no valid cgroup entry is found
        rescue => e
          Datadog.logger.debug(
            "Error while reading container entry. Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
          )
          @entry = Entry.new unless defined?(@entry)
          @entry
        end
      end
    end
  end
end
