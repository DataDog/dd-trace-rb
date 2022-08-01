# typed: false

module Datadog
  module Profiling
    module Collectors
      # TODO: Add description
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time_worker.c`
      class CpuAndWallTimeWorker
        def initialize(cpu_and_wall_time_collector:)
          self.class._native_initialize(self, cpu_and_wall_time_collector)
        end

        def start
          Thread.new do
            begin
              Thread.current.name = self.class.name unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')

              self.class._native_sampling_loop(self)
            rescue Exception => e
              @error = e
              Datadog.logger.warn(
                "Worker thread error. Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
              )
              raise
            end
          end
        end
      end
    end
  end
end
