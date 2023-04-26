# frozen_string_literal: true

require 'lib/datadog/tracing/contrib/aws/services/sqs'
require 'spec_helper'

RSpec.describe 'add_sqs_tags' do
  let(:span) { instance_double('Span') }
  let(:params) { {} }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'when queue_url is present' do
    let(:queue_url) { 'https://sqs.us-east-1.amazonaws.com/123456789012/MyQueueName' }
    let(:params) { { queue_url: queue_url } }

    it 'sets AWS account and queue name tags' do
      add_sqs_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_QUEUE_NAME, 'MyQueueName')
    end
  end

  context 'when queue_name is present' do
    let(:queue_name) { 'AnotherQueueName' }
    let(:params) { { queue_name: queue_name } }

    it 'sets queue name tag' do
      add_sqs_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_QUEUE_NAME, 'AnotherQueueName')
    end
  end
end
