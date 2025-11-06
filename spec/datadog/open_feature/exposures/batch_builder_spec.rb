# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/configuration/settings'
require 'datadog/open_feature/exposures/batch_builder'

RSpec.describe Datadog::OpenFeature::Exposures::BatchBuilder do
  subject(:builder) { described_class.new(settings) }

  describe '#payload_for' do
    context 'when settings expose env, service and version accessors' do
      let(:settings) do
        Datadog::Core::Configuration::Settings.new.tap do |c|
          c.env = 'prod'
          c.service = 'dummy-service'
          c.version = '1.0.0'
        end
      end
      let(:event) do
        Datadog::OpenFeature::Exposures::Models::Event.new(
          timestamp: 1_735_689_600_000,
          allocation: {key: 'control'},
          flag: {key: 'demo'},
          variant: {key: 'a'},
          subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
        )
      end

      it 'returns payload built from direct accessors' do
        expect(builder.payload_for([event])).to eq(
          context: {env: 'prod', service: 'dummy-service', version: '1.0.0'},
          exposures: [{
            timestamp: 1_735_689_600_000,
            allocation: {key: 'control'},
            flag: {key: 'demo'},
            variant: {key: 'a'},
            subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
          }]
        )
      end
    end

    context 'when settings only expose tags' do
      let(:settings) do
        instance_double(
          Datadog::Core::Configuration::Settings,
          tags: {'env' => 'staging', 'service' => 'tagged-service', 'version' => '2.1.3'}
        )
      end
      let(:events) do
        [
          Datadog::OpenFeature::Exposures::Models::Event.new(
            timestamp: 1_735_689_600_001,
            allocation: {key: 'group-a'},
            flag: {key: 'flag-a'},
            variant: {key: 'var-a'},
            subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
          ),
          Datadog::OpenFeature::Exposures::Models::Event.new(
            timestamp: 1_735_689_600_002,
            allocation: {key: 'group-b'},
            flag: {key: 'flag-b'},
            variant: {key: 'var-b'},
            subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
          )
        ]
      end

      it 'falls back to tag values when accessors are missing' do
        expect(builder.payload_for(events)).to eq(
          context: {env: 'staging', service: 'tagged-service', version: '2.1.3'},
          exposures: [
            {
              timestamp: 1_735_689_600_001,
              allocation: {key: 'group-a'},
              flag: {key: 'flag-a'},
              variant: {key: 'var-a'},
              subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
            },
            {
              timestamp: 1_735_689_600_002,
              allocation: {key: 'group-b'},
              flag: {key: 'flag-b'},
              variant: {key: 'var-b'},
              subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
            }
          ]
        )
      end
    end

    context 'when settings expose mixed accessors and tags' do
      let(:settings) do
        instance_double(
          Datadog::Core::Configuration::Settings, env: 'qa', tags: {'service' => 'tag-service'}
        )
      end
      let(:event) do
        Datadog::OpenFeature::Exposures::Models::Event.new(
          timestamp: 1_735_689_600_003,
          allocation: {key: 'group-c'},
          flag: {key: 'flag-c'},
          variant: {key: 'var-c'},
          subject: {id: 'user-2', attributes: {'plan' => 'basic'}}
        )
      end

      it 'uses available attributes and falls back to tags for others' do
        expect(builder.payload_for([event])).to eq(
          context: {env: 'qa', service: 'tag-service'},
          exposures: [{
            timestamp: 1_735_689_600_003,
            allocation: {key: 'group-c'},
            flag: {key: 'flag-c'},
            variant: {key: 'var-c'},
            subject: {id: 'user-2', attributes: {'plan' => 'basic'}}
          }]
        )
      end
    end

    context 'when settings provide no context information' do
      let(:settings) { instance_double(Datadog::Core::Configuration::Settings, tags: {}) }

      it 'returns payload with empty context and exposures' do
        expect(builder.payload_for([])).to eq(context: {}, exposures: [])
      end
    end
  end
end


