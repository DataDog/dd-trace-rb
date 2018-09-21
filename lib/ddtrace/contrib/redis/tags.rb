require 'ddtrace/ext/net'
require 'ddtrace/contrib/redis/ext'

module Datadog
  module Contrib
    module Redis
      # Tags handles generic common tags assignment.
      module Tags
        module_function

        def set_common_tags(client, span)
          span.set_tag Datadog::Ext::NET::TARGET_HOST, client.host
          span.set_tag Datadog::Ext::NET::TARGET_PORT, client.port
          span.set_tag Ext::TAG_DB, client.db
          span.set_tag Ext::TAG_RAW_COMMAND, span.resource
        end
      end
    end
  end
end
