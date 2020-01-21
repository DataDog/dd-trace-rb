module Instrument
  class << self
    def trace_before(receiver, method_name, span_name, &trace_block)
      trace_around(receiver, method_name, span_name) do |span, args, block|
        trace_block.call(span, args, block)
        yield
      end
    end

    def trace_around(receiver, method_name, span_name, &trace_block)
      trace_options = {} # TODO implement options

      m = Module.new do
        define_method method_name do |*args, &block|
          tracer = Datadog.tracer # TODO provide a custom tracer

          return unless tracer.enabled
          # TODO: define method with same visibility as original

          called = false
          original_return = nil

          original = -> do
            called = true
            original_return = super(*args, &block)
          rescue => e # TODO should I rescue all Exception instead, or StandardError is fine?
            # Instrument error first to allow for caller to
            # make changes the span error fields if necessary

            # TODO instrument_error(span)
            raise e
          end

          span = tracer.trace(span_name, trace_options)
          trace_block.call(span, args, block, &original)

          unless called
            Datadog::Logger.log.warn("Instrumentation forgot to yield to original method") # TODO better message
            original.call
          end

          original_return
        rescue => e # TODO should I rescue all Exception instead, or StandardError is fine?
          if called
            # Propagate error that occurred on the original method
            raise e
          else
            Datadog::Logger.log.error("Error instrumentation of #{self.class}.#{method_name}") # TODO better message
            original.call # Ensure we call original
          end
        ensure
          span.finish
        end
      end

      receiver.class.prepend m

      a = Class.new do
        prepend m
      end

      a.new.instrument

      receiver
    end

    # self.class.singleton_class.send(:prepend, m)
  end
end