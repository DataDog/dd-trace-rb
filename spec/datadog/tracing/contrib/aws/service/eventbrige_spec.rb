# frozen_string_literal: true

require 'datadog/tracing/contrib/aws/service/eventbridge'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::EventBridge do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:event_bridge) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with rule_name provided in params[:name]' do
    let(:rule_name) { 'example-rule-name' }
    let(:params) { { name: rule_name } }

    it 'sets the rule_name based on the params[:name]' do
      event_bridge.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_RULE_NAME, rule_name)
    end
  end

  context 'with rule_name provided in params[:rule]' do
    let(:rule_name) { 'example-rule-name' }
    let(:params) { { rule: rule_name } }

    it 'sets the rule_name based on the params[:rule]' do
      event_bridge.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_RULE_NAME, rule_name)
    end
  end

  context 'without rule_name provided' do
    it 'does not set the rule_name tag' do
      event_bridge.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_RULE_NAME, nil)
    end
  end
end
