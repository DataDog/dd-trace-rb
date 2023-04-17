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

        module_function

        # Retrieves number of classes from runtime
        def id
          @id ||= ::SecureRandom.uuid.freeze

          # Check if runtime has changed, e.g. forked.
          after_fork! { @id = ::SecureRandom.uuid.freeze }

          @id
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

        # Returns tracer version, rubygems-style
        def tracer_version
          Core::Environment::Ext::TRACER_VERSION
        end

        # Returns tracer version, comforming to https://semver.org/spec/v2.0.0.html
        def tracer_version_semver2
          # from ddtrace/version.rb, we have MAJOR.MINOR.PATCH plus an optional .PRE
          # - transform .PRE to -PRE if present
          # - keep triplet before that
          tracer_version.sub(/\.([a-zA-Z0-9]*[a-zA-Z][a-zA-Z0-9]*.*)$/, '-\1')
        end
      end
    end
  end
end
