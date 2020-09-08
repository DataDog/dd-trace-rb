require 'ddtrace/ext/environment'

module Datadog
  module OpenTelemetry
    # Extensions for Datadog::Span
    module Span
      TAG_SERVICE_NAME = 'service.name'.freeze
      TAG_SERVICE_VERSION = 'service.version'.freeze

      def set_tag(key, value)
        # Configure sampling priority if they give us a forced tracing tag
        # DEV: Do not set if the value they give us is explicitly "false"
        case key
        when TAG_SERVICE_NAME
          if defined?(super)
            # Set original tag and Datadog version tag
            self.service = value
            super
          end
        when TAG_SERVICE_VERSION
          if defined?(super)
            # Set original tag and Datadog version tag
            super
            super(Datadog::Ext::Environment::TAG_VERSION, value)
          end
        else
          # Otherwise, set the tag normally.
          super if defined?(super)
        end
      end
    end
  end
end
