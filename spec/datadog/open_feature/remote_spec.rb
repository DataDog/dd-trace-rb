# frozen_string_litral: true

require 'spec_helper'
require 'datadog/open_feature/remote'
require 'datadog/core/remote/configuration/repository'

RSpec.describe Datadog::OpenFeature::Remote do
  let(:remote) { described_class }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:receivers) { remote.receivers(telemetry) }
  let(:receiver) { receivers[0] }

  describe '.capabilities' do
    it { expect(remote.capabilities).to eq([70368744177664]) }
  end

  describe '.products' do
    it { expect(remote.products).to eq(['FFE_FLAGS']) }
  end

  describe '.receivers' do
    it 'returns receivers' do
      expect(receivers).to have(1).element
      expect(receiver).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
    end

    it 'matches FFE_FLAGS product paths' do
      path = Datadog::Core::Remote::Configuration::Path.parse('datadog/1/FFE_FLAGS/ufc-test/config')

      expect(receiver.match?(path)).to be(true)
    end
  end

  describe 'receiver logic' do
    before do
      allow(telemetry).to receive(:error)
      allow(Datadog::OpenFeature).to receive(:evaluator).and_return(evaluator)
    end

    let(:evaluator) { Datadog::OpenFeature::Evaluator.new(telemetry) }
    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
    let(:target) do
      Datadog::Core::Remote::Configuration::Target.parse(
        {
          'custom' => {'v' => 1},
          'hashes' => {'sha256' => Digest::SHA256.hexdigest(content_data)},
          'length' => content_data.length
        }
      )
    end
    let(:content) do
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: 'datadog/1/FFE_FLAGS/latest/config',
          content: StringIO.new(content_data)
        }
      )
    end
    let(:content_data) do
      <<~JSON
        {
          "data": {
            "type": "universal-flag-configuration",
            "id": "1",
            "attributes": {
              "createdAt": "2024-04-17T19:40:53.716Z",
              "format": "SERVER",
              "environment": { "name": "test" },
              "flags": {
                "test_flag": {
                  "key": "test_flag",
                  "enabled": true,
                  "variationType": "STRING",
                  "variations": {
                    "control": { "key": "control", "value": "control_value" }
                  },
                  "allocations": [
                    {
                      "key": "rollout",
                      "splits": [{ "variationKey": "control", "shards": [] }],
                      "doLog": false
                    }
                  ]
                }
              }
            }
          }
        }
      JSON
    end

    context 'when change type is insert' do
      let(:transaction) do
        repository.transaction { |_, t| t.insert(content.path, target, content) }
      end

      it 'reconfigures evaluator and acknowledges applied change' do
        expect(evaluator).to receive(:reconfigure!)

        receiver.call(repository, transaction)

        expect(evaluator.ufc_json).to eq(content_data)
        expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED)
      end
    end

    context 'when change type is update' do
      before do
        txn = repository.transaction { |_, t| t.insert(content.path, target, content) }
        receiver.call(repository, txn)
      end

      let(:transaction) do
        repository.transaction { |_, t| t.update(new_content.path, target, new_content) }
      end
      let(:new_content) do
        Datadog::Core::Remote::Configuration::Content.parse(
          {path: content.path.to_s, content: StringIO.new(new_content_data)}
        )
      end
      let(:new_content_data) do
        <<~JSON
          {
            "data": {
              "type": "universal-flag-configuration",
              "id": "1",
              "attributes": {
                "createdAt": "2024-04-17T19:40:53.716Z",
                "format": "SERVER",
                "environment": { "name": "test" },
                "flags": {}
              }
            }
          }
        JSON
      end

      it 'reconfigures evaluator and acknowledges applied change' do
        expect(evaluator).to receive(:reconfigure!)

        receiver.call(repository, transaction)

        expect(evaluator.ufc_json).to eq(new_content_data)
        expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED)
      end
    end

    context 'when change type is delete' do
      before do
        repository.transaction { |_r, t| t.insert(content.path, target, content) }
      end

      let(:transaction) do
        repository.transaction { |_, t| t.delete(content.path) }
      end

      it 'performs no-op on delete but reconfigures' do
        expect(evaluator).to receive(:reconfigure!)
        expect { receiver.call(repository, transaction) }.not_to raise_error
      end
    end

    context 'when content is missing' do
      let(:changes) do
        [
          instance_double(
            Datadog::Core::Remote::Configuration::Repository::Change::Updated,
            path: missing_path,
            type: :update,
          )
        ]
      end
      let(:missing_path) do
        Datadog::Core::Remote::Configuration::Path.parse('datadog/1/FFE_FLAGS/other/config')
      end

      it 'logs error when content missing and still reconfigures' do
        expect(telemetry).to receive(:error).with(/OpenFeature: RemoteConfig change is not present/)
        expect(evaluator).to receive(:reconfigure!)

        receiver.call(repository, changes)
      end
    end
  end
end
