require 'ddtrace/profiling/transport/io/client'

module Datadog
  module Profiling
    # Writes profiling data to transport
    class Exporter
      attr_reader \
        :transport

      def initialize(transport)
        unless transport.is_a?(Profiling::Transport::IO::Client)
          raise ArgumentError, 'Unsupported transport for profiling exporter.'
        end

        @transport = transport
      end

      def export(flushes)
        transport.send_flushes(flushes)
      end
    end
  end
end
