# frozen_string_literal: true

require 'logger'

module Datadog
  module Core
    # Process-wide logger that silently discards every message.
    #
    # Use this when an API requires a Logger but the caller has a structural
    # reason not to emit output — for example, settings-default blocks that
    # consult a downstream component's environment predicate, where the
    # downstream component will log the same condition with the real logger
    # at the right layer shortly afterward.
    #
    # Wraps stdlib `::Logger` pointed at `::IO::NULL` so the full Logger
    # interface (debug, info, warn, error, fatal, add, log) is available;
    # callers don't have to know they got a stub.
    #
    # The instance is frozen — do not reassign level, formatter, or any
    # other configurable property on it. If a caller needs a configurable
    # null sink, instantiate `::Logger.new(::IO::NULL)` directly rather
    # than mutating this shared constant.
    NULL_LOGGER = ::Logger.new(::IO::NULL).freeze
  end
end
