require 'securerandom'
require 'ddtrace/ext/runtime'
require 'ddtrace/utils/forking'

module Datadog
  module Runtime
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
        Ext::Runtime::LANG
      end

      def lang_engine
        Ext::Runtime::LANG_ENGINE
      end

      def lang_interpreter
        Ext::Runtime::LANG_INTERPRETER
      end

      def lang_platform
        Ext::Runtime::LANG_PLATFORM
      end

      def lang_version
        Ext::Runtime::LANG_VERSION
      end

      def tracer_version
        Ext::Runtime::TRACER_VERSION
      end
    end
  end
end
