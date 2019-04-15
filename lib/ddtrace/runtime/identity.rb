require 'securerandom'
require 'ddtrace/ext/runtime'

module Datadog
  module Runtime
    # For runtime identity
    module Identity
      module_function

      # Retrieves number of classes from runtime
      def id
        @pid ||= Process.pid
        @id ||= SecureRandom.uuid

        # Check if runtime has changed, e.g. forked.
        if Process.pid != @pid
          @pid = Process.pid
          @id = SecureRandom.uuid
        end

        @id
      end

      def lang
        Ext::Runtime::LANG
      end

      def lang_interpreter
        Ext::Runtime::LANG_INTERPRETER
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
