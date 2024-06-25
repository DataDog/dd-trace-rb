# frozen_string_literal: true

require_relative '../environment/platform'
require_relative '../utils/hash'

module Datadog
  module Core
    module Telemetry
      # Module defining methods for collecting metadata for telemetry
      module Request
        class << self
          using Core::Utils::Hash::Refinement

          def build_payload(event, seq_id)
            hash = {
              api_version: Http::Ext::API_VERSION,
              application: application,
              debug: false,
              host: host,
              payload: event.payload(seq_id),
              request_type: event.type,
              runtime_id: Core::Environment::Identity.id,
              seq_id: seq_id,
              tracer_time: Time.now.to_i,
            }
            hash.compact!
            hash
          end

          private

          def application
            config = Datadog.configuration
            {
              env: config.env,
              language_name: Core::Environment::Ext::LANG,
              language_version: Core::Environment::Ext::LANG_VERSION,
              runtime_name: Core::Environment::Ext::RUBY_ENGINE,
              runtime_version: Core::Environment::Ext::ENGINE_VERSION,
              service_name: config.service,
              service_version: config.version,
              tracer_version: Core::Environment::Identity.gem_datadog_version_semver2
            }
          end

          def host
            {
              architecture: Core::Environment::Platform.architecture,
              hostname: Core::Environment::Platform.hostname,
              kernel_name: Core::Environment::Platform.kernel_name,
              kernel_release: Core::Environment::Platform.kernel_release,
              kernel_version: Core::Environment::Platform.kernel_version
            }
          end
        end
      end
    end
  end
end
