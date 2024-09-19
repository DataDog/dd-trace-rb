# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/kinesis'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Kinesis do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:kinesis) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with stream_arn provided' do
    let(:stream_arn) { 'arn:aws:kinesis:us-east-1:123456789012:stream/my-stream' }
    let(:params) { { stream_arn: stream_arn } }

    it 'sets the stream_name and aws_account based on the stream_arn' do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, 'my-stream')
    end
  end

  context 'with stream_name provided' do
    let(:params) { { stream_name: 'my-stream' } }

    it 'sets the stream_name based on the provided stream_name' do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, 'my-stream')
    end
  end

  context 'with neither stream_arn nor stream_name provided' do
    it 'sets the stream_name to nil' do
      kinesis.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, nil)
    end
  end
end
