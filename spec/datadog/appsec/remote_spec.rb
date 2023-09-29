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
        expect(described_class.capabilities).to eq([4, 128, 16, 32, 64, 8, 256, 512])
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
    context 'remote configuration disabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(false)
      end

      it 'returns empty array' do
        expect(described_class.receivers).to eq([])
      end
    end

    context 'remote configuration enabled' do
      before do
        expect(described_class).to receive(:remote_features_enabled?).and_return(true)
      end

      it 'returns receivers' do
        receivers = described_class.receivers
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

        let(:receiver) { described_class.receivers[0] }

        let(:target) do
          Datadog::Core::Remote::Configuration::Target.parse(
            {
              'custom' => {
                'v' => 1,
              },
              'hashes' => { 'sha256' => Digest::SHA256.hexdigest(rules.to_json) },
              'length' => rules.to_s.length
            }
          )
        end

        let(:content) do
          Datadog::Core::Remote::Configuration::Content.parse(
            {
              path: 'datadog/603646/ASM_DD/latest/config',
              content: StringIO.new(rules)
            }
          )
        end

        let(:transaction) do
          repository.transaction do |_repository, transaction|
            transaction.insert(content.path, target, content)
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
            }],
            'processors' => Datadog::AppSec::Processor::RuleMerger::DEFAULT_WAF_PROCESSORS,
            'scanners' => Datadog::AppSec::Processor::RuleMerger::DEFAULT_WAF_SCANNERS,
          }

          expect(Datadog::AppSec).to receive(:reconfigure).with(ruleset: expected_ruleset, actions: [])
            .and_return(nil)
          changes = transaction
          receiver.call(repository, changes)
        end

        context 'content product' do
          before do
            # Stub the reconfigure method, so we do not trigger background reconfiguration
            allow(Datadog::AppSec).to receive(:reconfigure)
          end

          let(:default_ruleset) do
            [Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: Datadog.configuration.appsec.ruleset)]
          end

          let(:target) do
            Datadog::Core::Remote::Configuration::Target.parse(
              {
                'custom' => {
                  'v' => 1,
                },
                'hashes' => { 'sha256' => Digest::SHA256.hexdigest(data.to_json) },
                'length' => data.to_s.length
              }
            )
          end

          let(:content) do
            Datadog::Core::Remote::Configuration::Content.parse(
              {
                path: path,
                content: StringIO.new(data.to_json)
              }
            )
          end

          let(:rules_override) do
            [
              {
                'on_match' => [
                  'block'
                ],
                'rules_target' => [
                  {
                    'tags' => {
                      'confidence' => '1'
                    }
                  }
                ]
              }
            ]
          end

          let(:exclusions) do
            [
              {
                'conditions' => [
                  {
                    'operator' => 'ip_match',
                    'parameters' => {
                      'inputs' => [
                        {
                          'address' => 'http.client_ip'
                        }
                      ],
                      'list' => [
                        '3.3.3.10'
                      ]
                    }
                  }
                ],
                'id' => 'a9611f2c-3535-4546-9b7d-2249aafc9681'
              }
            ]
          end

          let(:rules_data) do
            [
              {
                'data' => [
                  {
                    'value' => '123.45.67.89'
                  },
                ]
              }
            ]
          end

          let(:custom_rules) do
            [
              {
                id: 'custom-rule-001',
                name: 'Block Friends IP Addresses',
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
              }.to_json
            ]
          end

          let(:actions) do
            [
              {
                'id' => 'block',
                'type' => 'block_request',
                'parameters' => {
                  'status_code' => 418,
                  'type' => 'auto'
                }
              }
            ]
          end

          context 'ASM' do
            let(:path) { 'datadog/603646/ASM/whatevername/config' }

            context 'overrides' do
              let(:data) do
                {
                  'rules_override' => rules_override
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [rules_override],
                  exclusions: [],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'exclusions' do
              let(:data) do
                {
                  'exclusions' => exclusions
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [],
                  exclusions: [exclusions],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'custom_rules' do
              let(:data) do
                {
                  'custom_rules' => custom_rules
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [],
                  exclusions: [],
                  custom_rules: [custom_rules]
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'actions' do
              let(:data) do
                {
                  'actions' => actions
                }
              end

              it 'pass the actions to reconfigure' do
                ruleset = Datadog::AppSec::Processor::RuleMerger.merge(rules: default_ruleset)

                expect(Datadog::AppSec).to receive(:reconfigure).with(ruleset: ruleset, actions: actions)
                  .and_return(nil)

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'multiple keys' do
              let(:data) do
                {
                  'rules_override' => rules_override,
                  'exclusions' => exclusions
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [rules_override],
                  exclusions: [exclusions],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'unsupported key' do
              let(:data) do
                {
                  'unsupported' => {}
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [],
                  exclusions: [],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end
          end

          context 'ASM_DATA' do
            let(:path) { 'datadog/603646/ASM_DATA/whatevername/config' }

            context 'with rules_data information' do
              let(:data) do
                {
                  'rules_data' => rules_data
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [rules_data],
                  overrides: [],
                  exclusions: [],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end

            context 'without rules_data information' do
              let(:data) do
                {
                  'other_key' => {}
                }
              end

              it 'pass the right values to RuleMerger' do
                expect(Datadog::AppSec::Processor::RuleMerger).to receive(:merge).with(
                  rules: default_ruleset,
                  data: [],
                  overrides: [],
                  exclusions: [],
                  custom_rules: [],
                )

                changes = transaction
                receiver.call(repository, changes)
              end
            end
          end

          context 'ASM_DD' do
            context 'no content' do
              let(:transaction) { repository.transaction { |repository, transaction| } }

              it 'uses the rules from the appsec settings' do
                ruleset = Datadog::AppSec::Processor::RuleMerger.merge(rules: default_ruleset)

                changes = transaction
                expect(Datadog::AppSec).to receive(:reconfigure).with(ruleset: ruleset, actions: [])
                  .and_return(nil)
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
  end
end
