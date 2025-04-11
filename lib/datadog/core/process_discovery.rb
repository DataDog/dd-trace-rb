# frozen_string_literal: true

module Datadog
  module Core
    # Class used to store tracer metadata in a native file descriptor.
    class ProcessDiscovery
      def self.get_and_store_metadata(settings)
        metadata = get_metadata(settings)
        _native_store_tracer_metadata(**metadata)
      end

      # According to RFC, runtime_id, service_name, service_env, service_version are optional.
      # ddcommon memfd_create exposer replace empty strings in these fields by None.
      def self.get_metadata(settings)
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
