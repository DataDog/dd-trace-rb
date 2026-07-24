# frozen_string_literal: true

require "securerandom"

require_relative "../configuration/config_helper"
require_relative "ext"
require_relative "../utils/forking"

module Datadog
  module Core
    module Environment
      # For runtime identity
      # @public_api
      module Identity
        extend Core::Utils::Forking

        ENV_ROOT_SESSION_ID = "_DD_ROOT_RB_SESSION_ID"
        ENV_PARENT_SESSION_ID = "_DD_PARENT_RB_SESSION_ID"

        module_function

        @root_runtime_id = DATADOG_ENV[ENV_ROOT_SESSION_ID]&.freeze
        @parent_runtime_id = DATADOG_ENV[ENV_PARENT_SESSION_ID]&.freeze

        def id
          @id ||= ::SecureRandom.uuid.freeze

          after_fork! do
            # Order matters: capture @id before overwriting
            @parent_runtime_id = @id
            @root_runtime_id ||= @id
            @id = ::SecureRandom.uuid.freeze
          end

          @id
        end

        def root_runtime_id
          @root_runtime_id
        end

        def parent_runtime_id
          @parent_runtime_id
        end

        def runtime_propagation_envs
          {ENV_ROOT_SESSION_ID => root_runtime_id || id, ENV_PARENT_SESSION_ID => id}.freeze
        end

        def pid
          ::Process.pid
        end

        def lang
          Core::Environment::Ext::LANG
        end

        def lang_engine
          Core::Environment::Ext::LANG_ENGINE
        end

        def lang_interpreter
          Core::Environment::Ext::LANG_INTERPRETER
        end

        def lang_platform
          Core::Environment::Ext::LANG_PLATFORM
        end

        def lang_version
          Core::Environment::Ext::LANG_VERSION
        end

        # Returns datadog gem version, rubygems-style
        def gem_datadog_version
          Core::Environment::Ext::GEM_DATADOG_VERSION
        end

        # Returns the tracer version in SemVer-2 form (https://semver.org/spec/v2.0.0.html).
        #
        # Converts the RubyGems-style version returned by {.gem_datadog_version}
        # (dot-separated prerelease/build segments, e.g. "2.34.0.dev") into the
        # SemVer-2 form expected by cross-language Datadog consumers (hyphen-separated
        # prerelease, "+" build metadata, e.g. "2.34.0-dev").
        #
        # Called by reporters that emit a tracer version on the wire and must match
        # the format used by other-language tracers:
        # - process discovery memfd (`Core::ProcessDiscovery.get_metadata` → `tracer_version`)
        # - telemetry payloads (`Core::Telemetry::Request#application`)
        # - remote configuration client identification (`Core::Remote::Client#tracer_version`)
        #
        # Use {.gem_datadog_version} (not this method) when a RubyGems-style string is
        # required (e.g. gem-internal contexts, gemspec interop).
        def gem_datadog_version_semver2
          major, minor, patch, rest = gem_datadog_version.split(".", 4)

          semver = "#{major}.#{minor}.#{patch}"

          return semver unless rest

          pre = ""
          build = ""

          rest.split(".").tap do |segments|
            if segments.length >= 4
              pre = "-#{segments.shift}"
              build = "+#{segments.join(".")}"
            elsif segments.length == 1
              pre = "-#{segments.shift}"
            else
              build = "+#{segments.join(".")}"
            end
          end

          semver + pre + build
        end
      end
    end
  end
end
