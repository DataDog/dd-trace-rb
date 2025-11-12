# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/configuration/settings'
require 'datadog/open_feature/exposures/batch_builder'

RSpec.describe Datadog::OpenFeature::Exposures::BatchBuilder do
  subject(:builder) { described_class.new(settings) }

  describe '#payload_for' do
    let(:event) do
      {
        timestamp: 1_735_689_600_000,
        allocation: {key: 'control'},
        flag: {key: 'demo'},
        variant: {key: 'a'},
        subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
      }
    end

    context 'when env, service, and version are present' do
      let(:settings) do
        Datadog::Core::Configuration::Settings.new.tap do |c|
          c.env = 'prod'
          c.service = 'dummy-service'
          c.version = '1.0.0'
        end
      end

      it 'returns payload with context fields' do
        expect(builder.payload_for([event])).to eq(
          context: {env: 'prod', service: 'dummy-service', version: '1.0.0'},
          exposures: [event]
        )
      end
    end

    context 'when service is nil' do
      let(:settings) do
        instance_double(
          Datadog::Core::Configuration::Settings,
          env: 'qa',
          service: nil,
          version: '2.0.0'
        )
      end

      it 'ignores nil context values' do
        expect(builder.payload_for([event])).to eq(
          context: {env: 'qa', version: '2.0.0'},
          exposures: [event]
        )
      end
    end

    context 'when settings provide no context information' do
      let(:settings) do
        instance_double(
          Datadog::Core::Configuration::Settings,
          env: nil,
          service: nil,
          version: nil
        )
      end

      it 'returns payload with empty context' do
        expect(builder.payload_for([event])).to eq({context: {}, exposures: [event]})
      end
    end
  end
end
