require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/integration_examples'

require 'aws-sdk'
require 'ddtrace'
require 'ddtrace/contrib/aws/patcher'
require 'ddtrace/ext/http'

RSpec.describe 'AWS instrumentation' do
  let(:configuration_options) { {} }

  before do
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

  context 'with a core AWS SDK client', if: RUBY_VERSION >= '2.2.0' do
    before { hide_const('Aws::S3') }

    let(:client) { ::Aws::STS::Client.new(stub_responses: responses) } # STS is part of aws-sdk-core

    describe '#get_access_key_info' do
      subject!(:get_access_key_info) { client.get_access_key_info(access_key_id: 'dummy') }
      let(:responses) { { get_access_key_info: { account: 'test account' } } }

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false
      it_behaves_like 'a peer service span'

      it 'generates a span' do
        expect(span.name).to eq('aws.command')
        expect(span.service).to eq('aws')
        expect(span.span_type).to eq('http')
        expect(span.resource).to eq('sts.get_access_key_info')

        expect(span.get_tag('aws.agent')).to eq('aws-sdk-ruby')
        expect(span.get_tag('aws.operation')).to eq('get_access_key_info')
        expect(span.get_tag('aws.region')).to eq('us-stubbed-1')
        expect(span.get_tag('path')).to eq('')
        expect(span.get_tag('host')).to eq('sts.us-stubbed-1.amazonaws.com')
        expect(span.get_tag('http.method')).to eq('POST')
        expect(span.get_tag('http.status_code')).to eq('200')
      end

      it 'returns an unmodified response' do
        expect(get_access_key_info.account).to eq('test account')
      end
    end
  end

  context 'with an S3 client' do
    let(:client) { ::Aws::S3::Client.new(stub_responses: responses) }

    describe '#list_buckets' do
      subject!(:list_buckets) { client.list_buckets }

      let(:responses) do
        { list_buckets: { buckets: [{ name: 'bucket1' }] } }
      end

      it_behaves_like 'analytics for integration' do
        let(:analytics_enabled_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false

      it 'generates a span' do
        expect(span.name).to eq('aws.command')
        expect(span.service).to eq('aws')
        expect(span.span_type).to eq('http')
        expect(span.resource).to eq('s3.list_buckets')

        expect(span.get_tag('aws.agent')).to eq('aws-sdk-ruby')
        expect(span.get_tag('aws.operation')).to eq('list_buckets')
        expect(span.get_tag('aws.region')).to eq('us-stubbed-1')
        expect(span.get_tag('path')).to eq('/')
        expect(span.get_tag('host')).to eq('s3.us-stubbed-1.amazonaws.com')
        expect(span.get_tag('http.method')).to eq('GET')
        expect(span.get_tag('http.status_code')).to eq('200')
      end

      it_behaves_like 'a peer service span'

      it 'returns an unmodified response' do
        expect(list_buckets.buckets.map(&:name)).to eq(['bucket1'])
      end
    end

    describe 'S3::Presigner' do
      let(:presigner) { ::Aws::S3::Presigner.new(client: client) }

      describe '#presigned_url' do
        subject!(:presign) { presigner.presigned_url(:get_object, bucket: 'bucket', key: 'key') }

        # presigned_url returns a string instead of a Seahorse object, so it does not accept
        # object stubbing like other S3 methods. We simply tell it to enable stubbing and it
        # will return a stubbed URL without hitting the remote.
        let(:responses) { { presigned_url: true } }

        it 'does not instrument presign as an HTTP request' do
          presign

          expect(spans).to be_empty
        end

        it 'returns an unmodified response' do
          expect(presign).to start_with('https://bucket.s3.us-stubbed-1.amazonaws.com/key')
        end
      end
    end
  end
end
