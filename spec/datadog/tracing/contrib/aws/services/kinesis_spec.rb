# frozen_string_literal: true

require 'rspec'
require 'lib/datadog/tracing/contrib/aws/services/kinesis'

RSpec.describe 'add_kinesis_tags' do
  let(:span) { instance_double('Span') }
  let(:params) { {} }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with stream_arn provided' do
    let(:stream_arn) { 'arn:aws:kinesis:us-east-1:123456789012:stream/my-stream' }
    let(:params) { { stream_arn: stream_arn } }

    it 'sets the stream_name and aws_account based on the stream_arn' do
      add_kinesis_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, 'my-stream')
    end
  end

  context 'with stream_name provided' do
    let(:params) { { stream_name: 'my-stream' } }

    it 'sets the stream_name based on the provided stream_name' do
      add_kinesis_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, 'my-stream')
    end
  end

  context 'with neither stream_arn nor stream_name provided' do
    it 'sets the stream_name to nil' do
      add_kinesis_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, nil)
    end
  end
end
