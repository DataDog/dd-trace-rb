# frozen_string_literal: true

require 'securerandom'

require_relative 'ext'
require_relative '../utils/forking'

module Datadog
  module Core
    module Environment
      # For runtime identity
      # @public_api
      module Identity
        extend Core::Utils::Forking

        ENV_ROOT_SESSION_ID = '_DD_ROOT_RB_SESSION_ID'
        ENV_PARENT_SESSION_ID = '_DD_PARENT_RB_SESSION_ID'

        module_function

        # Seed from env when this process was spawned (Process.spawn, exec).
        # For fork-based processes these are set by after_fork!.
        @ancestor_runtime_id = ENV[ENV_ROOT_SESSION_ID]&.freeze
        @parent_runtime_id = ENV[ENV_PARENT_SESSION_ID]&.freeze

        # Retrieves number of classes from runtime
        def id
          @id ||= ::SecureRandom.uuid.freeze

          # Check if runtime has changed, e.g. forked.
          after_fork! do
            @parent_runtime_id = @id
            @ancestor_runtime_id ||= @id
            @id = ::SecureRandom.uuid.freeze
          end

          @id
        end

        # Root of the fork tree (Stable Service Instance Identifier). Nil in root process.
        def ancestor_runtime_id
          @ancestor_runtime_id
        end

        # Direct parent's runtime_id. Nil in root process.
        def parent_runtime_id
          @parent_runtime_id
        end

        # Returns session lineage env vars to inject into child process environments.
        # Allows exec-based child processes (Process.spawn) to reconstruct process lineage.
        def runtime_propagation_envs
          ancestor = ancestor_runtime_id
          current = id
          root = ancestor || current
          { ENV_ROOT_SESSION_ID => root, ENV_PARENT_SESSION_ID => current }.freeze
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

        # Returns tracer version, comforming to https://semver.org/spec/v2.0.0.html
        def gem_datadog_version_semver2
          major, minor, patch, rest = gem_datadog_version.split('.', 4)

          semver = "#{major}.#{minor}.#{patch}"

          return semver unless rest

          pre = ''
          build = ''

          rest.split('.').tap do |segments|
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
