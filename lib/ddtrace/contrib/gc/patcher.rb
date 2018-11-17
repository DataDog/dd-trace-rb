module Datadog
  module Contrib
    module GC
      # Installs a hook into the runtime to be called after GC events have
      # been traced.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:gc)
        end

        def patch
          do_once(:gc) do
            # The hook is called from within a signal/trap context, so we have
            # to actually record the trace on a separate thread outside of
            # that context.
            queue = Queue.new

            Datadog::Runtime.current.report_gc do |trace|
              queue.push(trace)
            end

            Thread.new do
              loop do
                trace = queue.pop
                break unless trace
                trace_gc(trace)
              end
            end
          end
        end

        def trace_gc(trace)
          span = Datadog.tracer.trace(
            Ext::SPAN_GC,
            service: Datadog.configuration[:gc][:service_name],
            span_type: nil,
            start_time: trace[:start]
          )
          span.finish(trace[:end])
        rescue => e
          Datadog::Tracer.log.error("GC trace failed: #{e}")
        end
      end
    end
  end
end
