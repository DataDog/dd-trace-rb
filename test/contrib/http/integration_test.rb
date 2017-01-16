require 'time'
require 'contrib/elasticsearch/test_helper'
require 'helper'

class HTTPIntegrationTest < Minitest::Test
  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer (to make a real integration test)
    @tracer = Datadog.tracer
  end

  def test_request
    true
  end
end
