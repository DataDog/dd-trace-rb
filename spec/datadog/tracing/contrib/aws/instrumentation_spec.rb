require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'aws-sdk'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'ddtrace'
require 'datadog/tracing/contrib/aws/patcher'

RSpec.describe 'AWS instrumentation' do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :aws, configuration_options
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
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration'
      it_behaves_like 'a peer service span'
      it_behaves_like 'environment service name', 'DD_TRACE_AWS_SERVICE_NAME'

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
        expect(span.get_tag('span.kind')).to eq('client')

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('aws')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('command')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('aws')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq('sts.us-stubbed-1.amazonaws.com')
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
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration'
      it_behaves_like 'environment service name', 'DD_TRACE_AWS_SERVICE_NAME'

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
        expect(span.get_tag('span.kind')).to eq('client')

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('aws')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('command')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('aws')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq('s3.us-stubbed-1.amazonaws.com')
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
