require 'datadog/core/environment/identity'
require 'datadog/core/environment/socket'

module Datadog
  module Profiling
    # Entity class used to represent metadata for a given profile
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
      :profiler_version,
      :tags
    ) do
      def initialize(*args)
        super
        self.runtime_id = runtime_id || Datadog::Core::Environment::Identity.id
        self.service = service || Datadog.configuration.service
        self.env = env || Datadog.configuration.env
        self.version = version || Datadog.configuration.version
        self.host = host || Datadog::Core::Environment::Socket.hostname
        self.language = language || Datadog::Core::Environment::Identity.lang
        self.runtime_engine = runtime_engine || Datadog::Core::Environment::Identity.lang_engine
        self.runtime_platform = runtime_platform || Datadog::Core::Environment::Identity.lang_platform
        self.runtime_version = runtime_version || Datadog::Core::Environment::Identity.lang_version
        self.profiler_version = profiler_version || Datadog::Core::Environment::Identity.tracer_version
        self.tags = tags || Datadog.configuration.tags
      end
    end

    # Represents a collection of events of a specific type being flushed.
    EventGroup = Struct.new(:event_class, :events).freeze
  end
end
