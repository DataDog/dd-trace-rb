require 'securerandom'
require 'datadog/core/ext/environment'
require 'ddtrace/utils/forking'

module Datadog
  module Core
    module Environment
      # For runtime identity
      module Identity
        extend Datadog::Utils::Forking

        module_function

        # Retrieves number of classes from runtime
        def id
          @id ||= SecureRandom.uuid

          # Check if runtime has changed, e.g. forked.
          after_fork! { @id = SecureRandom.uuid }

          @id
        end

        def lang
          Core::Ext::Environment::LANG
        end

        def lang_engine
          Core::Ext::Environment::LANG_ENGINE
        end

        def lang_interpreter
          Core::Ext::Environment::LANG_INTERPRETER
        end

        def lang_platform
          Core::Ext::Environment::LANG_PLATFORM
        end

        def lang_version
          Core::Ext::Environment::LANG_VERSION
        end

        def tracer_version
          Core::Ext::Environment::TRACER_VERSION
        end
      end
    end
  end
end
