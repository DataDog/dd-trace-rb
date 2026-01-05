require 'datadog/appsec/spec_helper'
require 'datadog/appsec/remote'
require 'datadog/core/remote/configuration/repository'

RSpec.describe Datadog::AppSec::Remote do
  describe '.capabilities' do
    context 'remote configuration disabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.capabilities).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(true)
      end

      it 'returns capabilities' do
        expect(described_class.capabilities).to eq([
          4, 128, 16, 32, 64, 8, 256, 512, 1024, 65_536, 131_072, 8_388_608, 2_097_152, 2_147_483_648,
          4_294_967_296, 8_589_934_592, 17_179_869_184, 34_359_738_368, 8_796_093_022_208
        ])
      end
    end
  end

  describe '.products' do
    context 'remote configuration disabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.products).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(true)
      end

      it 'returns products' do
        expect(described_class.products).to eq(['ASM_DD', 'ASM', 'ASM_FEATURES', 'ASM_DATA'])
      end
    end
  end

  describe '.receivers' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
    let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine) }

    context 'remote configuration disabled' do
      before do
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
        allow(described_class).to receive(:remote_features_enabled?).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.receivers(telemetry)).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
        allow(described_class).to receive(:remote_features_enabled?).and_return(true)
      end

      it 'returns receivers' do
        receivers = described_class.receivers(telemetry)
        expect(receivers.size).to eq(1)
        expect(receivers.first).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
      end

      context 'receiver logic' do
        let(:rules) do
          {
            version: '2.2',
            metadata: {
              rules_version: '1.5.2'
            },
            rules: [
              {
                id: 'blk-001-001',
                name: 'Block IP Addresses',
                tags: {
                  type: 'block_ip',
                  category: 'security_response'
                },
                conditions: [
                  {
                    parameters: {
                      inputs: [
                        {
                          address: 'http.client_ip'
                        }
                      ],
                      data: 'blocked_ips'
                    },
                    operator: 'ip_match'
                  }
                ],
                transformers: [],
                on_match: [
                  'block'
                ]
              }
            ]
          }.to_json
        end

        let(:receiver) { described_class.receivers(telemetry)[0] }

        let(:target) do
          Datadog::Core::Remote::Configuration::Target.parse(
            {
              'custom' => {
                'v' => 1,
              },
              'hashes' => {'sha256' => Digest::SHA256.hexdigest(rules.to_json)},
              'length' => rules.to_s.length
            }
          )
        end

        let(:content) do
          Datadog::Core::Remote::Configuration::Content.parse(
            {
              path: 'datadog/603646/ASM_DD/latest/config',
              content: rules,
            }
          )
        end

        let(:transaction) do
          repository.transaction do |_repository, transaction|
            transaction.insert(content.path, target, content)
          end
        end

        let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

        let(:settings) do
          Datadog::Core::Configuration::Settings.new.tap do |settings|
            settings.appsec.enabled = true
          end
        end

        let(:appsec_component) do
          Datadog::AppSec::Component.build_appsec_component(settings, telemetry: telemetry)
        end

        before do
          allow(Datadog::AppSec).to receive(:security_engine).and_return(appsec_component.security_engine)
        end

        it 'propagates changes to AppSec' do
          expect(Datadog::AppSec.security_engine).to receive(:add_or_update_config).with(
            JSON.parse(rules), path: content.path.to_s
          )

          expect(Datadog::AppSec).to receive(:reconfigure!)

          receiver.call(repository, transaction)
        end

        it 'sets apply_state to ACKNOWLEDGED on content' do
          receiver.call(repository, transaction)

          expect(content.apply_state).to eq(Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED)
        end
      end
    end
  end
end
