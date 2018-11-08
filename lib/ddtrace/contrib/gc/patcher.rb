module Datadog
  module Contrib
    module GC
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
            
            Datadog::NativeGC.hook = -> (trace) do
              queue.push trace
            end

            Thread.new do
              while trace = queue.pop
                trace_gc trace
              end
            end
          end
        end

        def trace_gc(trace)
          begin
            span = Datadog.tracer.trace(
              'gc',
              service: Datadog.configuration[:gc][:service_name],
              span_type: 'gc',
              start_time: trace[:start],
            )
            span.finish(trace[:end])
          rescue => err
            Datadog::Tracer.log.error("GC trace failed: #{e}")
          end
        end
      end
    end
  end
end
