# frozen_string_literal: true

require 'logger'

module Datadog
  module Core
    # Process-wide logger that silently discards every message.
    #
    # Use this when an API requires a Logger but the caller has a structural
    # reason not to emit output — for example, a settings-default block that
    # consults a downstream component's environment predicate. Such a block is
    # evaluated lazily on the first config read, which can happen before,
    # after, or independently of the component being built, so emitting from
    # it would log at the wrong layer (and, depending on read order,
    # redundantly). The component that owns the predicate logs the condition
    # with the real logger when it evaluates the predicate during its own
    # build; this sink keeps the config-read path silent.
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
