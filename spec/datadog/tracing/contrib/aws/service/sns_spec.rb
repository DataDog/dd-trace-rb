# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/sns'
require_relative 'shared_examples'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::SNS do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:sns) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with topic_arn provided' do
    let(:topic_arn) { 'arn:aws:sns:us-west-2:123456789012:my-topic-name' }
    let(:params) { { topic_arn: topic_arn } }

    it 'sets the topic_name and aws_account based on the topic_arn' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with name provided' do
    let(:params) { { name: 'my-topic-name' } }

    it 'sets the topic_name based on the provided name' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, 'my-topic-name')
    end
  end

  context 'with neither topic_arn nor name provided' do
    it 'sets the topic_name to nil' do
      sns.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, nil)
    end
  end

  it_behaves_like 'injects AWS attribute propagation' do
    let(:service) { sns }
    let(:operation) { :publish }
    let(:data_type) { 'Binary' }
  end
end
