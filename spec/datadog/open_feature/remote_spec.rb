# frozen_string_litral: true

require "spec_helper"
require "datadog/open_feature/remote"
require "datadog/core/remote/configuration/repository"

RSpec.describe Datadog::OpenFeature::Remote do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:receivers) { described_class.receivers(telemetry) }
  let(:receiver) { receivers[0] }
  let(:logger) { instance_double(Datadog::Core::Logger) }

  describe ".capabilities" do
    it { expect(described_class.capabilities).to eq([70368744177664]) }
  end

  describe ".products" do
    it { expect(described_class.products).to eq(["FFE_FLAGS"]) }
  end

  describe ".receivers" do
    it "returns receivers" do
      expect(receivers).to have(1).element
      expect(receiver).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
    end

    it "matches FFE_FLAGS product paths" do
      path = Datadog::Core::Remote::Configuration::Path.parse("datadog/1/FFE_FLAGS/ufc-test/config")

      expect(receiver.match?(path)).to be(true)
    end
  end

  describe "receiver logic" do
    before do
      allow(telemetry).to receive(:error)
      allow(Datadog).to receive(:send).with(:components).and_return(components)
      allow(components).to receive(:open_feature).and_return(component)
    end

    let(:components) { instance_double(Datadog::Core::Configuration::Components) }
    let(:component) { instance_double(Datadog::OpenFeature::Component) }
    let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }
    let(:target) do
      Datadog::Core::Remote::Configuration::Target.parse(
        {
          "custom" => {"v" => 1},
          "hashes" => {"sha256" => Digest::SHA256.hexdigest(content_data)},
          "length" => content_data.length,
        }
      )
    end
    let(:content) do
      Datadog::Core::Remote::Configuration::Content.parse(
        {
          path: "datadog/1/FFE_FLAGS/latest/config",
          content: content_data,
        }
      )
    end
    let(:content_data) do
      <<~JSON
        {
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
      JSON
    end

    context "when change type is insert" do
      let(:transaction) do
        repository.transaction { |_, t| t.insert(content.path, target, content) }
      end

      it "reconfigures the component and acknowledges the applied change" do
        expect(component).to receive(:reconfigure!).with(content_data)

        receiver.call(repository, transaction)

        expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED)
      end
    end

    context "when change type is insert and reconfigure fails" do
      before { allow(component).to receive(:reconfigure!).and_raise(error) }

      let(:error) { Datadog::OpenFeature::EvaluationEngine::ReconfigurationError.new("Ooops") }
      let(:transaction) do
        repository.transaction { |_, t| t.insert(content.path, target, content) }
      end

      it "marks content as errored" do
        receiver.call(repository, transaction)

        expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ERROR)
      end
    end

    context "when change type is update" do
      before do
        allow(component).to receive(:reconfigure!)
        allow(Datadog::OpenFeature::NativeEvaluator).to receive(:new)
          .and_return(instance_double(Datadog::OpenFeature::NativeEvaluator))

        txn = repository.transaction { |_, t| t.insert(content.path, target, content) }
        receiver.call(repository, txn)
      end

      let(:transaction) do
        repository.transaction { |_, t| t.update(new_content.path, target, new_content) }
      end
      let(:new_content) do
        Datadog::Core::Remote::Configuration::Content.parse(
          {path: content.path.to_s, content: new_content_data}
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

      it "reconfigures the component and acknowledges the applied change" do
        expect(component).to receive(:reconfigure!).with(new_content_data)

        receiver.call(repository, transaction)

        expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED)
      end
    end

    context "when change type is delete" do
      before do
        repository.transaction { |_r, t| t.insert(content.path, target, content) }
      end

      let(:transaction) do
        repository.transaction { |_, t| t.delete(content.path) }
      end

      it "performs no-op on delete but reconfigures" do
        expect(component).to receive(:reconfigure!)
        expect { receiver.call(repository, transaction) }.not_to raise_error
      end
    end

    context "when content is missing" do
      let(:changes) do
        [
          instance_double(
            Datadog::Core::Remote::Configuration::Repository::Change::Updated,
            path: missing_path,
            type: :update,
          ),
        ]
      end
      let(:missing_path) do
        Datadog::Core::Remote::Configuration::Path.parse("datadog/1/FFE_FLAGS/other/config")
      end

      it "logs error when content is missing and does not reconfigure the component" do
        expect(telemetry).to receive(:error).with(/Remote Configuration change is not present/)
        expect(component).not_to receive(:reconfigure!)

        receiver.call(repository, changes)
      end
    end

    context "when component is unavailable" do
      let(:component) { nil }

      it { expect { receiver.call(repository, []) }.not_to raise_error }
    end
  end
end
