# frozen_string_literal: true

require_relative "ext"

module Datadog
  module Core
    module Environment
      # Reads information from Linux cgroups.
      # This information is used to extract information
      # about the current Linux container identity.
      # @see https://man7.org/linux/man-pages/man7/cgroups.7.html
      module Cgroup
        # A parsed cgroup entry from /proc/<pid>/cgroup
        Entry = Struct.new(
          :hierarchy,
          :controllers,
          :path,
          :inode,
        )

        # Parses the /proc/self/cgroup file,
        # @return [Array<Entry>] one entry for each valid cgroup line
        def self.entries
          filepath = "/proc/self/cgroup"
          return [] unless File.exist?(filepath)

          ret = []
          File.foreach(filepath) do |entry_line|
            # Without chomp, a bare cgroup v2 line ("0::/") keeps its newline in the path,
            # so the inode lookup fails and no container identity is sent.
            line = entry_line.chomp
            ret << parse(line) unless line.empty?
          end
          ret
        end

        # Parses a single cgroup entry from /proc/<pid>/cgroup.
        #
        # Files can have cgroup v1 and v2 entries mixed. Their format is the same.
        #
        # Each entry has 3 colon-separated fields:
        #   hierarchy-ID:controllers:path
        # Examples:
        #   10:memory:/docker/1234567890abcdef (cgroup v1)
        #   0::/docker/1234567890abcdef (cgroup v2)
        #
        # @see https://man7.org/linux/man-pages/man7/cgroups.7.html#:~:text=%2Fproc%2Fpid%2Fcgroup
        # @return [Entry]
        def self.parse(entry_line)
          hierarchy, controllers, path = entry_line.split(":", 3)

          Entry.new(
            hierarchy,
            controllers,
            path,
            inode_for(controllers, path),
          )
        end

        # We can find the container inode by running a file stat on the cgroup filesystem path.
        # Example:
        #   For the entry `0:cpu:/docker/abc123`,
        #   we read `stat -c '%i' /sys/fs/cgroup/cpu/docker/abc123`
        def self.inode_for(controllers, path)
          return if controllers.nil? || path.nil?

          # In cgroup v1, when multiple controllers are co-mounted, the controllers
          # becomes part of the directory name (with commas preserved).
          # Example entry:
          #   For the line "10:cpu,cpuacct:/docker/abc123", the path is
          #   "/sys/fs/cgroup/cpu,cpuacct/docker/abc123"
          inode_path = File.join("/sys/fs/cgroup", controllers, path)

          File.stat(inode_path).ino if File.exist?(inode_path)
        end
      end
    end
  end
end
