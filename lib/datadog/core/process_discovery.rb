# frozen_string_literal: true

require 'datadog/core/process_discovery/tracer_memfd'

require_relative 'utils/at_fork_monkey_patch'
require_relative 'utils/only_once'

module Datadog
  module Core
    # Class used to store tracer metadata in a native file descriptor.
    class ProcessDiscovery
      ONLY_ONCE = Core::Utils::OnlyOnce.new

      class << self
        def get_and_store_metadata(settings, logger)
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            logger.debug("Cannot enable process discovery: #{libdatadog_api_failure}")
            return
          end

          ONLY_ONCE.run { apply_at_fork_patch }

          metadata = get_metadata(settings)

          shutdown!
          @file_descriptor = _native_store_tracer_metadata(logger, **metadata)
          @file_descriptor&.logger = logger
        end

        def shutdown!
          @file_descriptor&.shutdown!
          @file_descriptor = nil
        end

        private

        # According to the RFC, runtime_id, service_name, service_env, service_version are optional.
        # In the C method exposed by ddcommon, memfd_create replaces empty strings by None for these fields.
        def get_metadata(settings)
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

        def apply_at_fork_patch
          Utils::AtForkMonkeyPatch.apply!
          Utils::AtForkMonkeyPatch.at_fork(:child) do
            next if (components = Datadog.send(:components, allow_initialization: false)).nil?

            logger = components.logger
            get_and_store_metadata(Datadog.configuration, logger)
          end
        end
      end
    end
  end
end
