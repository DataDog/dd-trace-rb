# frozen_string_literal: true

require 'datadog/core/process_discovery/tracer_memfd'

require_relative 'utils/at_fork_monkey_patch'
require_relative 'utils/only_once'

module Datadog
  module Core
    # Class used to store tracer metadata in a native file descriptor.
    module ProcessDiscovery
      ONLY_ONCE = Core::Utils::OnlyOnce.new

      class << self
        def publish(settings)
          if (libdatadog_api_failure = Datadog::Core::LIBDATADOG_API_FAILURE)
            Datadog.logger.debug { "Cannot enable process discovery: #{libdatadog_api_failure}" }
            return
          end

          ONLY_ONCE.run { apply_at_fork_patch }

          metadata = get_metadata(settings)

          shutdown!
          @file_descriptor = _native_store_tracer_metadata(Datadog.logger, **metadata)
        end

        def shutdown!
          @file_descriptor&.shutdown!(Datadog.logger)
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
          # The runtime-id changes after a fork. We apply this patch to at_fork to ensure that the runtime-id is updated.
          Utils::AtForkMonkeyPatch.apply!
          Utils::AtForkMonkeyPatch.at_fork(:child) { publish(Datadog.configuration) }
        end
      end
    end
  end
end
