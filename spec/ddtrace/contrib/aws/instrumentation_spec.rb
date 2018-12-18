require 'spec_helper'

require 'aws-sdk'
require 'ddtrace'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/ext/http'

RSpec.describe 'AWS instrumentation' do
  let(:tracer) { get_test_tracer }

  let(:client) { ::Aws::S3::Client.new(stub_responses: responses) }
  let(:responses) { true }

  let(:span) { spans.first }
  let(:spans) { tracer.writer.spans(:keep) }

  before(:each) do
    Datadog.configure do |c|
      c.use :aws, tracer: tracer
    end
  end

  context 'when the client runs' do
    describe '#list_buckets' do
      subject!(:list_buckets) { client.list_buckets }

      let(:responses) do
        { list_buckets: { buckets: [{ name: 'bucket1' }] } }
      end

      it 'generates a span' do
        expect(span.name).to eq('aws.command')
        expect(span.service).to eq('aws')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('s3.list_buckets')

        expect(span.get_tag('aws.agent')).to eq('aws-sdk-ruby')
        expect(span.get_tag('aws.operation')).to eq('list_buckets')
        expect(span.get_tag('aws.region')).to eq('us-stubbed-1')
        expect(span.get_tag('path')).to eq('/')
        expect(span.get_tag('host')).to eq('s3.us-stubbed-1.amazonaws.com')
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
      end

      it 'returns the correct response' do
        expect(list_buckets.buckets.map(&:name)).to eq(['bucket1'])
      end
    end
  end
end
