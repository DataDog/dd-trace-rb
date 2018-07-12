require('helper')
require('aws-sdk')
require('ddtrace/contrib/aws/parsed_context')
class ParsedContextTest < Minitest::Test
  before do
    @client = Aws::S3::Client.new(region: 'us-west-2', stub_responses: true)
  end
  it('context parsing') do
    response = @client.list_buckets
    context = Datadog::Contrib::Aws::ParsedContext.new(response.context)
    expect(context.resource).to(eq('s3.list_buckets'))
    expect(context.operation).to(eq(:list_buckets))
    expect(context.status_code).to(eq(200))
    expect(context.http_method).to(eq('GET'))
    expect(context.region).to(eq('us-west-2'))
    expect(context.retry_attempts).to(eq(0))
    expect(context.path).to(eq('/'))
    assert_includes(context.host, 'us-west-2.amazonaws.com')
  end
  it('context param safety') do
    response = @client.list_buckets
    context = Datadog::Contrib::Aws::ParsedContext.new(response.context)
    context.stub(:resource, -> { raise }) do
      actual = context.safely(:resource, 'fallback_name')
      expect(actual).to(eq('fallback_name'))
    end
  end
end
