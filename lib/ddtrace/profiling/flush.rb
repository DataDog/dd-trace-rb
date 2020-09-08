require 'ddtrace/runtime/identity'
require 'ddtrace/runtime/socket'

module Datadog
  module Profiling
    # Represents a flush of all profiling events
    Flush = Struct.new(
      :start,
      :finish,
      :event_groups,
      :event_count,
      :runtime_id,
      :service,
      :env,
      :version,
      :host,
      :language,
      :runtime_engine,
      :runtime_platform,
      :runtime_version,
      :profiler_version
    ) do
      def initialize(*args)
        super
        self.runtime_id = runtime_id || Datadog::Runtime::Identity.id
        self.service = service || Datadog.configuration.service
        self.env = env || Datadog.configuration.env
        self.version = version || Datadog.configuration.version
        self.host = host || Datadog::Runtime::Socket.hostname
        self.language = language || Datadog::Runtime::Identity.lang
        self.runtime_engine = runtime_engine || Datadog::Runtime::Identity.lang_engine
        self.runtime_platform = runtime_platform || Datadog::Runtime::Identity.lang_platform
        self.runtime_version = runtime_version || Datadog::Runtime::Identity.lang_version
        self.profiler_version = profiler_version || Datadog::Runtime::Identity.tracer_version
      end
    end

    # Represents a collection of events of a specific type being flushed.
    EventGroup = Struct.new(:event_class, :events).freeze
  end
end
