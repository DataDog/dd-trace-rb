require 'datadog/appsec/spec_helper'
require 'datadog/appsec/remote'
require 'datadog/core/remote/configuration/repository'

RSpec.describe Datadog::AppSec::Remote do
  describe '.capabilities' do
    context 'remote configuration disabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.capabilities).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(true)
      end

      it 'returns capabilities' do
        expect(described_class.capabilities).to eq([4, 128, 256, 16, 32, 64, 8])
      end
    end
  end

  describe '.products' do
    context 'remote configuration disabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.products).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(true)
      end

      it 'returns products' do
        expect(described_class.products).to eq(['ASM_DD', 'ASM', 'ASM_FEATURES', 'ASM_DATA'])
      end
    end
  end

  describe '.receivers' do
    context 'remote configuration disabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.receivers).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(Datadog::AppSec).to receive(:default_setting?).with(:ruleset).and_return(true)
      end

      it 'returns receivers' do
        receivers = described_class.receivers
        expect(receivers.size).to eq(1)
        expect(receivers.first).to be_a(Datadog::Core::Remote::Dispatcher::Receiver)
      end

      context 'receiver logic' do
        let(:rules_data) do
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
        let(:receiver) { described_class.receivers[0] }
        let(:transaction) do
          repository.transaction do |_repository, transaction|
            content = Datadog::Core::Remote::Configuration::Content.parse(
              {
                path: 'datadog/603646/ASM_DD/latest/config',
                content: StringIO.new(rules_data)
              }
            )
            transaction.insert(content.path, nil, content)
          end
        end
        let(:repository) { Datadog::Core::Remote::Configuration::Repository.new }

        it 'propagates changes to AppSec' do
          expected_ruleset = {
            'version' => '2.2',
            'metadata' => {
              'rules_version' => '1.5.2'
            },
            'rules' => [{
              'id' => 'blk-001-001',
              'name' => 'Block IP Addresses',
              'tags' => {
                'type' => 'block_ip', 'category' => 'security_response'
              },
              'conditions' => [{
                'parameters' => {
                  'inputs' => [{
                    'address' => 'http.client_ip'
                  }], 'data' => 'blocked_ips'
                },
                'operator' => 'ip_match'
              }],
              'transformers' => [],
              'on_match' => ['block']
            }]
          }

          expect(Datadog::AppSec).to receive(:reconfigure).with(ruleset: expected_ruleset)
          changes = transaction
          receiver.call(repository, changes)
        end

        context 'when there is no ASM_DD information' do
          let(:transaction) { repository.transaction { |repository, transaction| } }
          it 'uses the rules from the appsec settings' do
            expect(Datadog::AppSec::Processor::RuleLoader).to receive(:load_rules).with(
              ruleset: Datadog.configuration.appsec.ruleset
            ).at_least(:once).and_call_original

            changes = transaction
            receiver.call(repository, changes)
          end

          it 'raises SyncError if no default rules available' do
            expect(Datadog::AppSec::Processor::RuleLoader).to receive(:load_rules).with(
              ruleset: Datadog.configuration.appsec.ruleset
            ).and_return(nil)

            changes = transaction

            expect { receiver.call(repository, changes) }.to raise_error(described_class::NoRulesError)
          end
        end
      end
    end
  end
end
