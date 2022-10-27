# typed: false

module Datadog
  module Tracing
    module Contrib
      module Propagation
        module SqlComment
          module Ext
            ENV_SQL_COMMENT_PROPAGATION_MODE = 'DD_TRACE_SQL_COMMENT_PROPAGATION_MODE'.freeze

            # The default mode for sql comment propagation
            DISABLED = 'disabled'.freeze

            # The `service` mode propagates service configuration
            SERVICE = 'service'.freeze

            # The `full` mode propagates service configuration + trace context
            FULL = 'full'.freeze

            # The value should be `true` when `full` mode
            TAG_DBM_TRACE_INJECTED = '_dd.dbm_trace_injected'.freeze

            KEY_DATABASE_SERVICE = 'dddbs'.freeze
            KEY_ENVIRONMENT = 'dde'.freeze
            KEY_PARENT_SERVICE = 'ddps'.freeze
            KEY_VERSION = 'ddpv'.freeze
          end
        end
      end
    end
  end
end
