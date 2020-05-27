require 'ddtrace/profiling/transport/io/client'

module Datadog
  module Profiling
    # Writes profiling data to transport
    class Exporter
      attr_reader \
        :transport

      def initialize(transport)
        @transport = transport

        case @transport
        when Datadog::Transport::IO::Client
          @transport.extend(Profiling::Transport::IO::Client)
        else
          raise ArgumentError, 'Unsupported transport for profiling exporter.'
        end
      end

      def export(flushes)
        transport.send_flushes(flushes)
      end
    end
  end
end
