require 'helper'
require 'aws-sdk'
require 'ddtrace/contrib/aws/parsed_context'

class ParsedContextTest < Minitest::Test
  def setup
    @client = Aws::S3::Client.new(region: 'us-west-2', stub_responses: true)
  end

  def test_context_parsing
    response = @client.list_buckets
    context = Datadog::Contrib::Aws::ParsedContext.new(response.context)
    assert_equal('s3.list_buckets', context.resource)
    assert_equal(:list_buckets, context.operation)
    assert_equal(200, context.status_code)
    assert_equal('GET', context.http_method)
    assert_equal('us-west-2', context.region)
    assert_equal(0, context.retry_attempts)
    assert_equal('/', context.path)
    assert_equal('s3-us-west-2.amazonaws.com', context.host)
  end

  def test_context_param_safety
    response = @client.list_buckets
    context = Datadog::Contrib::Aws::ParsedContext.new(response.context)
    context.stub :resource, -> { raise } do
      actual = context.safely(:resource, 'fallback_name')
      assert_equal('fallback_name', actual)
    end
  end
end
