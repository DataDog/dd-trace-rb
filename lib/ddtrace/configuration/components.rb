require 'ddtrace/tracer'

module Datadog
  module Configuration
    # Global components for the trace library.
    class Components
      def initialize(settings); end

      def teardown!; end
    end
  end
end
