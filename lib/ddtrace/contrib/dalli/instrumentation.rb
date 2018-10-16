require 'ddtrace/ext/net'
require 'ddtrace/contrib/dalli/quantize'

module Datadog
  module Contrib
    module Dalli
      # Instruments every interaction with the memcached server
      module Instrumentation
        module_function

        def patch!
          ::Dalli::Server.class_eval do
            alias_method :__request, :request

            def request(op, *args)
              pin = Datadog::Pin.get_from(::Dalli)

              pin.tracer.trace(Datadog::Contrib::Dalli::Ext::SPAN_COMMAND) do |span|
                span.resource = op.to_s.upcase
                span.service = pin.service
                span.span_type = pin.app_type
                span.set_tag(Datadog::Ext::NET::TARGET_HOST, hostname)
                span.set_tag(Datadog::Ext::NET::TARGET_PORT, port)
                cmd = Datadog::Contrib::Dalli::Quantize.format_command(op, args)
                span.set_tag(Datadog::Contrib::Dalli::Ext::TAG_COMMAND, cmd)

                __request(op, *args)
              end
            end
          end
        end
      end
    end
  end
end
