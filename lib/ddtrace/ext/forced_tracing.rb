module Datadog
  module Ext
    # Defines constants for forced tracing
    module ForcedTracing
      TAG_KEEP = 'manual.drop'.freeze
      TAG_DROP = 'manual.keep'.freeze
    end
  end
end
