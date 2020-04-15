require 'ddtrace/ext/runtime'

module Datadog
  module Runtime
    # For control groups
    module Cgroup
      LINE_REGEX = /^(\d+):([^:]*):(.+)$/

      Descriptor = Struct.new(
        :id,
        :groups,
        :path,
        :controllers
      )

      module_function

      def descriptors(process = 'self')
        [].tap do |descriptors|
          begin
            filepath = "/proc/#{process}/cgroup"

            if File.exist?(filepath)
              File.open("/proc/#{process}/cgroup").each do |line|
                line = line.strip
                descriptors << parse(line) unless line.empty?
              end
            end
          rescue StandardError => e
            Datadog.logger.error("Error while parsing cgroup. Cause: #{e.message} Location: #{e.backtrace.first}")
          end
        end
      end

      def parse(line)
        id, groups, path = line.scan(LINE_REGEX).first

        Descriptor.new(id, groups, path).tap do |descriptor|
          descriptor.controllers = groups.split(',') unless groups.nil?
        end
      end
    end
  end
end
