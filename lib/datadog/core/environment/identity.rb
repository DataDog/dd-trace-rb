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

        def tracer_version
          Core::Environment::Ext::TRACER_VERSION
        end
      end
    end
  end
end
