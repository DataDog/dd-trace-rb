require('spec_helper')
require('aws-sdk')
require('ddtrace/contrib/aws/parsed_context')

RSpec.describe Datadog::Contrib::Aws::ParsedContext do
  before do
    @client = Aws::S3::Client.new(region: 'us-west-2', stub_responses: true)
  end
  it('context parsing') do
    response = @client.list_buckets
    context = described_class.new(response.context)
    expect(context.resource).to(eq('s3.list_buckets'))
    expect(context.operation).to(eq(:list_buckets))
    expect(context.status_code).to(eq(200))
    expect(context.http_method).to(eq('GET'))
    expect(context.region).to(eq('us-west-2'))
    expect(context.retry_attempts).to(eq(0))
    expect(context.path).to(eq('/'))
    expect(context.host).to include('us-west-2.amazonaws.com')
  end
  it('context param safety') do
    response = @client.list_buckets
    context = described_class.new(response.context)
    allow(context).to receive(:resource).and_raise

    expect(context.safely(:resource, 'fallback_name')).to(eq('fallback_name'))
  end
end
