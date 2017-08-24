require 'helper'
require 'aws-sdk'
require 'ddtrace/contrib/aws/parsed_context'

class ParsedContextTest < Minitest::Test
  def setup
    @client = Aws::S3::Client.new(region: 'us-west-2', stub_responses: true)
    response = @client.list_buckets
    @context = Datadog::Contrib::Aws::ParsedContext.new(response.context)
  end

  def test_resource
    assert_equal('s3.list_buckets', @context.resource)
  end

  def test_operation
    assert_equal(:list_buckets, @context.operation)
  end

  def test_status_code
    assert_equal(200, @context.status_code)
  end

  def test_http_method
    assert_equal('GET', @context.http_method)
  end

  def test_region
    assert_equal('us-west-2', @context.region)
  end

  def test_retry_attempts
    assert_equal(0, @context.retry_attempts)
  end

  def test_path
    assert_equal('/', @context.path)
  end

  def test_host
    assert_equal('s3-us-west-2.amazonaws.com', @context.host)
  end

  def test_param_safety
    @context.stub :resource, -> { raise } do
      actual = @context.safely(:resource, 'fallback_name')
      assert_equal('fallback_name', actual)
    end
  end
end
