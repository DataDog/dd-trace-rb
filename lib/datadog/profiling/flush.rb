# typed: false
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
      :code_provenance,
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
      def initialize(
        start:,
        finish:,
        event_groups:,
        event_count:,
        code_provenance:,
        runtime_id: Core::Environment::Identity.id,
        service: Datadog.configuration.service,
        env: Datadog.configuration.env,
        version: Datadog.configuration.version,
        host: Core::Environment::Socket.hostname,
        language: Core::Environment::Identity.lang,
        runtime_engine: Core::Environment::Identity.lang_engine,
        runtime_platform: Core::Environment::Identity.lang_platform,
        runtime_version: Core::Environment::Identity.lang_version,
        profiler_version: Core::Environment::Identity.tracer_version,
        tags: Datadog.configuration.tags
      )
        super(
          start,
          finish,
          event_groups,
          event_count,
          code_provenance,
          runtime_id,
          service,
          env,
          version,
          host,
          language,
          runtime_engine,
          runtime_platform,
          runtime_version,
          profiler_version,
          tags,
        )
      end
    end

    # Represents a collection of events of a specific type being flushed.
    EventGroup = Struct.new(:event_class, :events).freeze
  end
end
