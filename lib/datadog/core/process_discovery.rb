# frozen_string_literal: true

require 'datadog/core/process_discovery/tracer_memfd'
require 'datadog/core/utils/at_fork_monkey_patch'
require 'datadog/core/utils/only_once'

module Datadog
  module Core
    # Class used to store tracer metadata in a native file descriptor.
    class ProcessDiscovery
      ACTIVATE_FORKING_PATCH = Core::Utils::OnlyOnce.new

      def self.get_and_store_metadata(settings, logger)
        if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
          logger.debug("Cannot enable process discovery: #{libdatadog_api_failure}")
          return
        end
        metadata = get_metadata(settings)
        memfd = _native_store_tracer_metadata(logger, **metadata)
        memfd.logger = logger if memfd

        ACTIVATE_FORKING_PATCH.run do
          Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:child) do
            settings = Datadog.configuration
            Datadog::Core::ProcessDiscovery._native_publish_otel_ctx_on_fork(
              settings.env || '',
              Core::Environment::Socket.hostname,
              Core::Environment::Identity.id,
              settings.service || '',
              settings.version || '',
              Core::Environment::Identity.gem_datadog_version_semver2,
              Datadog.logger,
            )
          end
        end

        memfd
      end

      # According to the RFC, runtime_id, service_name, service_env, service_version are optional.
      # In the C method exposed by ddcommon, memfd_create replaces empty strings by None for these fields.
      private_class_method def self.get_metadata(settings)
        {
          schema_version: 1,
          runtime_id: Core::Environment::Identity.id,
          tracer_language: Core::Environment::Identity.lang,
          tracer_version: Core::Environment::Identity.gem_datadog_version_semver2,
          hostname: Core::Environment::Socket.hostname,
          service_name: settings.service || '',
          service_env: settings.env || '',
          service_version: settings.version || ''
        }
      end
    end
  end
end
