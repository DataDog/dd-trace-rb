require_relative 'datadog_interceptor'

module GRPC
  class InterceptionContext
    # :nodoc:
    # The `#intercept!` method is implemented in gRPC; this module
    # will be prepended to the original class, effectively injecting
    # our tracing middleware into the head of the call chain.
    module InterceptWithDatadog
      def intercept!(type, args = {})
        unless defined?(@trace_started) && @trace_started
          datadog_interceptor = choose_datadog_interceptor(args)

          @interceptors.unshift(datadog_interceptor.new) if datadog_interceptor

          @trace_started = true
        end

        super
      end

      private

      def choose_datadog_interceptor(args)
        if args.key?(:metadata)
          Datadog::Contrib::GRPC::DatadogInterceptor::Client
        elsif args.key?(:call)
          Datadog::Contrib::GRPC::DatadogInterceptor::Server
        end
      end
    end
  end
end
