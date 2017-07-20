require 'contrib/rack/helpers'
require 'contrib/http/test_helper'

# Below a quick example on how to hack and modify the standard headers.
Datadog::Monkey.without_warnings do # get rid of overriden constants warning
  module Datadog
    module Ext
      module DistributedTracing
        # These values can be used to communicate trace relationships
        # across multiple languages, so it's not recommended to modify
        # them, but should you want to do it, you can override them like this.
        HTTP_HEADER_TRACE_ID = 'x-custom-distributed-tracing-trace-id'.freeze
        HTTP_HEADER_PARENT_ID = 'x-custom-distributed-tracing-parent-id'.freeze
      end
    end
    module Contrib
      module Rack
        # Note the fact these are:
        # 1 - uppercased
        # 2 - '-' is replaced by '_'
        HTTP_HEADER_TRACE_ID = 'HTTP_X_CUSTOM_DISTRIBUTED_TRACING_TRACE_ID'.freeze
        HTTP_HEADER_PARENT_ID = 'HTTP_X_CUSTOM_DISTRIBUTED_TRACING_PARENT_ID'.freeze
      end
    end
  end
end

# require this *AFTER* the previous monkey patching, need to patch before running the test
require 'contrib/rack/distributed_test'

class CustomHeadersTest < DistributedTest
  def setup
    @tracer = get_test_tracer
    @rack_port = DistributedTest::RACK_PORT + 1
  end

  def test_net_http_get
    super
  end
end
