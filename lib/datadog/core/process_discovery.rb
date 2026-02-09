# frozen_string_literal: true

require 'datadog/core/process_discovery/tracer_memfd'
require 'datadog/core/environment/process'
require 'datadog/core/environment/container'

module Datadog
  module Core
    # Class used to store tracer metadata in a native file descriptor.
    module ProcessDiscovery
      class << self
        def publish(settings)
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            Datadog.logger.debug { "Cannot enable process discovery: #{libdatadog_api_failure}" }
            return
          end

          metadata = get_metadata(settings)

          shutdown!
          @file_descriptor = _native_store_tracer_metadata(Datadog.logger, **metadata)
        end

        def shutdown!
          @file_descriptor&.shutdown!(Datadog.logger)
          @file_descriptor = nil
        end

        def after_fork
          # The runtime-id changes after a fork. We call publish to ensure that the runtime-id is updated.
          publish(Datadog.configuration)
        end

        private

        # According to the RFC, runtime_id, service_name, service_env, service_version are optional.
        # In the C method exposed by ddcommon, memfd_create replaces empty strings by None for these fields.
        def get_metadata(settings)
          {
            runtime_id: Core::Environment::Identity.id,
            tracer_language: Core::Environment::Identity.lang,
            tracer_version: Core::Environment::Identity.gem_datadog_version_semver2,
            hostname: Core::Environment::Socket.hostname,
            service_name: settings.service || '',
            service_env: settings.env || '',
            service_version: settings.version || '',
            # Follows Java: https://github.com/DataDog/dd-trace-java/blob/master/dd-trace-core/src/main/java/datadog/trace/core/servicediscovery/ServiceDiscovery.java#L37-L38
            process_tags: Core::Environment::Process.serialized || '',
            container_id: Core::Environment::Container.container_id || ''
          }
        end
      end
    end
  end
end
