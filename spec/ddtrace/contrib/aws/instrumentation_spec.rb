require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'aws-sdk'
require 'ddtrace'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/ext/http'

RSpec.describe 'AWS instrumentation' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  let(:client) { ::Aws::S3::Client.new(stub_responses: responses) }
  let(:responses) { true }

  let(:span) { spans.first }
  let(:spans) { tracer.writer.spans(:keep) }

  before(:each) do
    Datadog.configure do |c|
      c.use :aws, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:aws].reset_configuration!
    example.run
    Datadog.registry[:aws].reset_configuration!
  end

  context 'when the client runs' do
    describe '#list_buckets' do
      subject!(:list_buckets) { client.list_buckets }

      let(:responses) do
        { list_buckets: { buckets: [{ name: 'bucket1' }] } }
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
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
        expect(span.get_tag('http.status_code')).to eq(200)
      end

      it 'returns the correct response' do
        expect(list_buckets.buckets.map(&:name)).to eq(['bucket1'])
      end
    end
  end
end
