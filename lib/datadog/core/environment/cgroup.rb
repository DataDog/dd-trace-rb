require 'datadog/core/environment/ext'

module Datadog
  module Core
    module Environment
      # For control groups
      module Cgroup
        LINE_REGEX = /^(\d+):([^:]*):(.+)$/.freeze

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
                File.foreach("/proc/#{process}/cgroup") do |line|
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
end
