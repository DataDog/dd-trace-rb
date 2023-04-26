# frozen_string_literal: true

require 'rspec'
require 'lib/datadog/tracing/contrib/aws/services/sns'

RSpec.describe 'add_sns_tags' do
  let(:span) { instance_double('Span') }
  let(:params) { {} }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with topic_arn provided' do
    let(:topic_arn) { 'arn:aws:sns:us-west-2:123456789012:my-topic-name' }
    let(:params) { { topic_arn: topic_arn } }

    it 'sets the topic_name and aws_account based on the topic_arn' do
      add_sns_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with name provided' do
    let(:params) { { name: 'my-topic-name' } }

    it 'sets the topic_name based on the provided name' do
      add_sns_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with neither topic_arn nor name provided' do
    it 'sets the topic_name to nil' do
      add_sns_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, nil)
    end
  end
end
