# frozen_string_literal: true

require 'set'
require 'json'

module Datadog
  module Profiling
    module Collectors
      # Collects SystemInfo data of relevance for profiler. This will get sent alongside
      # the profile and show up in the UI or influence processing.
      class SystemInfo
        def initialize(settings)
          @settings = settings
          refresh
        end

        attr_reader :system_info

        def refresh
          @system_info = {
            platform: collect_platform_info,
            runtime: collect_runtime_info,
            application: collect_application_info,
            profiler: collect_profiler_info,
          }
          self
        end

        private

        # Instead of trying to figure out real process start time by checking
        # /proc or some other complex/non-portable way, approximate start time
        # by time of requirement of this file.
        START_TIME = Time.now.utc.freeze

        def collect_platform_info
          @platform_info ||= {
            container_id: Datadog::Core::Environment::Container.container_id,
            hostname: Datadog::Core::Environment::Platform.hostname,
            kernel_name: Datadog::Core::Environment::Platform.kernel_name,
            kernel_release: Datadog::Core::Environment::Platform.kernel_release,
            kernel_version: Datadog::Core::Environment::Platform.kernel_version
          }
        end

        def collect_runtime_info
          @runtime_info ||= {
            engine: Datadog::Core::Environment::Identity.lang_engine,
            version: Datadog::Core::Environment::Identity.lang_version,
            platform: Datadog::Core::Environment::Identity.lang_platform,
          }
        end

        def collect_application_info
          @application_info ||= {
            start_time: START_TIME.iso8601,
            env: @settings.env,
            service: @settings.service,
            version: @settings.version,
          }
        end

        def collect_profiler_info
          unless @profiler_info
            lib_datadog_gem = ::Gem.loaded_specs['libdatadog']
            @profiler_info = {
              version: Datadog::Core::Environment::Identity.tracer_version,
              libdatadog: "#{lib_datadog_gem.version}-#{lib_datadog_gem.platform}",
              settings: collect_settings_recursively(@settings.profiling),
            }
          end
          @profiler_info
        end

        # The settings/option model isn't directly serializable because
        # of subsettings and options that link to full blown custom object
        # instances without proper serialization.
        # This method navigates a settings object recursively, converting
        # it into more basic types that are trivially convertible to JSON.
        def collect_settings_recursively(v)
          v = v.options_hash if v.respond_to?(:options_hash)

          if v.is_a?(Numeric) || v.is_a?(String) || v === true || v === false
            v
          elsif v.is_a?(Hash)
            collected_hash = v.each_with_object({}) do |(key, value), hash|
              collected_value = collect_settings_recursively(value)
              hash[key] = collected_value unless collected_value.nil?
            end
            collected_hash.empty? ? nil : collected_hash
          elsif v.is_a?(Enumerable)
            collected_list = v
              .map { |value| collect_settings_recursively(value) }
              .reject(&:is_nil?)
            collected_list.empty? ? nil : collected_list
          end
        end
      end
    end
  end
end
