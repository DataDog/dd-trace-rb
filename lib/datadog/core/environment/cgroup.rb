# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Core
    module Environment
      # Reads information from Linux cgroups.
      # This information is used to extract information
      # about the current Linux container identity.
      # @see https://man7.org/linux/man-pages/man7/cgroups.7.html
      module Cgroup
        # A regex to parse each line of /proc/<pid>/cgroup.
        # Each line has 3 fields separated by ':': hierarchy ID, controller list, cgroup path.
        # Examples:
        #   "10:memory:/docker/1234567890abcdef" (cgroup v1)
        #   "0::/docker/1234567890abcdef" (cgroup v2)
        LINE_REGEX = /^(?<hierarchy_id>\d+):(?<controller_list>[^:]*):(?<cgroup_path>.+)$/.freeze

        # From https://github.com/torvalds/linux/blob/5859a2b1991101d6b978f3feb5325dad39421f29/include/linux/proc_ns.h#L41-L49
        # Currently, host namespace inode number are hardcoded, which can be used to detect
        # if we're running in host namespace or not (does not work when running in DinD)
        HostCgroupNamespaceInode = 0xEFFFFFFB

        # cgroupV1BaseController is the base controller used to identify the cgroup v1 mount point
        CGROUP_V1_BASE_CONTROLLER = 'memory'

        # Default cgroup mount path
        DEFAULT_CGROUP_MOUNT_PATH = '/sys/fs/cgroup'

        Descriptor = Struct.new(
          :id,
          :groups,
          :path,
          :controllers
        )

        module_function

        def descriptors(process = 'self')
          [].tap do |descriptors|
            filepath = "/proc/#{process}/cgroup"

            if File.exist?(filepath)
              File.foreach("/proc/#{process}/cgroup") do |line|
                line = line.strip
                descriptors << parse(line) unless line.empty?
              end
            end
          rescue => e
            Datadog.logger.error(
              "Error while parsing cgroup. Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
            )
          end
        end

        def parse(line)
          id, groups, path = line.scan(LINE_REGEX).first

          descriptor = Descriptor.new(id, groups, path, get_inode(groups, path))
          descriptor.controllers = groups.split(',') unless groups.nil?
          descriptor
        end

        # Read inode by running a file stat on the cgroup path.
        # Example: for the cgroup entry `0::/`, we read `stat -c '%i' /sys/fs/cgroup/`.
        def get_inode(groups, path)
          inode_path = File.join('/sys/fs/cgroup', groups || '', path)

          File.stat(path).ino if File.exist?(inode_path)
        end

        # Checks if the current process is running on the host cgroup namespace.
        # This indicates that the process is not running inside a container.
        # When unsure, it returns `false`.
        def running_on_host?
          if File.exist?('/proc/self/ns/cgroup')
            File.stat('/proc/self/ns/cgroup').ino == HostCgroupNamespaceInode
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
    end
  end
end
