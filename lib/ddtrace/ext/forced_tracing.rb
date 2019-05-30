require 'ddtrace/ext/manual_tracing'
require 'ddtrace/patcher'

module Datadog
  module Ext
    # Defines constants for forced tracing
    module ForcedTracing
      TAG_KEEP = 'manual.keep'.freeze
      TAG_DROP = 'manual.drop'.freeze

      deprecate_constant :TAG_KEEP, :TAG_DROP
    end
  end
end
