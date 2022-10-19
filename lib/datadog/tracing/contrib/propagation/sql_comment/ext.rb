# typed: false

module Datadog
  module Tracing
    module Contrib
      module Propagation
        module SqlComment
          module Ext
            ENV_SQL_COMMENT_PROPAGATION_MODE = 'DD_TRACE_SQL_COMMENT_PROPAGATION_MODE'.freeze

            DISABLED = 'disabled'.freeze
            SERVICE = 'service'.freeze
            FULL = 'full'.freeze
          end
        end
      end
    end
  end
end
