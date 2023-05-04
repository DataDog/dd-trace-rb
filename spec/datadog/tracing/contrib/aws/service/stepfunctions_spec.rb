# frozen_string_literal: true

require 'rspec'
require 'lib/datadog/tracing/contrib/aws/service/base'
require 'lib/datadog/tracing/contrib/aws/service/stepfunctions'

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::States do
  let(:span) { instance_double('Span') }
  let(:params) { {} }
  let(:step_functions) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context 'with execution_arn provided' do
    let(:execution_arn) { 'arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution' }
    let(:params) { { execution_arn: execution_arn } }

    it 'sets the state_machine_name based on the execution_arn' do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(
        Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME,
        'example-state-machine'
      )
    end
  end

  context 'with state_machine_arn provided' do
    let(:state_machine_arn) { 'arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine' }
    let(:params) { { state_machine_arn: state_machine_arn } }

    it 'sets the state_machine_name based on the state_machine_arn' do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(
        Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME,
        'MyStateMachine'
      )
    end

    it 'sets the state_machine_account_id based on the state_machine_arn' do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
    end
  end

  context 'with both execution_arn and state_machine_arn provided' do
    let(:execution_arn) { 'arn:aws:states:us-east-1:987654321098:execution:example-state-machine:example-execution' }
    let(:state_machine_arn) { 'arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine' }

    it 'sets the state_machine_name and state_machine_account_id based on the state_machine_arn' do
      params = { state_machine_arn: state_machine_arn }
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '123456789012')
      expect(span).to have_received(:set_tag).with(
        Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME,
        'MyStateMachine'
      )
    end

    it 'sets the state_machine_name and state_machine_account_id based on the execution_arn' do
      params = { execution_arn: execution_arn }
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, '987654321098')
      expect(span).to have_received(:set_tag).with(
        Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME,
        'example-state-machine'
      )
    end
  end
end
