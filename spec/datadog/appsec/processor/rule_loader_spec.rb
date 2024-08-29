require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor/rule_loader'

RSpec.describe Datadog::AppSec::Processor::RuleLoader do
  describe '#load_ruleset' do
    let(:basic_ruleset) do
      {
        'version' => '1.0',
        'events' => [
          {
            'id' => 1,
            'name' => 'Rule 1',
            'tags' => { 'type' => 'flow1' },
            'conditions' => [
              { 'operation' => 'match_regex', 'parameters' => { 'inputs' => ['value2'], 'regex' => 'rule1' } },
            ],
            'action' => 'record',
          }
        ]
      }
    end
    let(:recommended) { JSON.parse(Datadog::AppSec::Assets.waf_rules(:recommended)) }
    let(:strict) { JSON.parse(Datadog::AppSec::Assets.waf_rules(:strict)) }

    subject(:rules) { described_class.load_rules(ruleset: ruleset) }

    context 'when ruleset is :recommended' do
      let(:ruleset) { :recommended }

      it do
        expect(rules).to_not be_nil
        expect(rules).to eq(recommended)
      end
    end

    context 'when ruleset is :strict' do
      let(:ruleset) { :strict }

      it do
        expect(rules).to_not be_nil
        expect(rules).to eq(strict)
      end
    end

    context 'when ruleset is :risky, defaults to recommended' do
      let(:ruleset) { :risky }

      it do
        expect(rules).to_not be_nil
        expect(rules).to eq(recommended)
      end
    end

    context 'when ruleset is an existing path' do
      let(:ruleset) { "#{__dir__}../../../../../lib/datadog/appsec/assets/waf_rules/recommended.json" }

      it { expect(rules).to_not be_nil }
    end

    context 'when ruleset is a non existing path' do
      let(:ruleset) { '/does/not/exist' }

      it 'returns `nil`' do
        expect(Datadog::Core::Telemetry::Logging).to receive(:report).with(
          an_instance_of(Errno::ENOENT),
          level: :error,
          description: 'libddwaf ruleset failed to load'
        )

        expect(rules).to be_nil
      end
    end

    context 'when ruleset is IO-like' do
      let(:ruleset) { StringIO.new(JSON.dump(basic_ruleset)) }

      it do
        expect(rules).to_not be_nil
        expect(rules).to eq(basic_ruleset)
      end
    end

    context 'when ruleset is Ruby' do
      let(:ruleset) { basic_ruleset }

      it do
        expect(rules).to_not be_nil
        expect(rules).to eq(basic_ruleset)
      end
    end

    context 'when ruleset is not parseable' do
      let(:ruleset) { StringIO.new('this is not json') }

      it 'returns `nil`' do
        expect(Datadog::Core::Telemetry::Logging).to receive(:report).with(
          an_instance_of(JSON::ParserError),
          level: :error,
          description: 'libddwaf ruleset failed to load'
        )

        expect(rules).to be_nil
      end
    end
  end

  describe '#load_data' do
    let(:ip_denylist) { [] }
    let(:user_id_denylist) { [] }
    subject(:data) { described_class.load_data(ip_denylist: ip_denylist, user_id_denylist: user_id_denylist) }

    context 'empty data' do
      it 'returns []' do
        expect(data).to eq([])
      end
    end

    context 'non empty data' do
      context 'with ip_denylist' do
        let(:ip_denylist) { ['1.1.1.1', '1.1.1.2'] }

        it 'returns data information' do
          expect(data).to_not be_nil
          expect(data.size).to eq 1
          rules_data = data[0][0]

          expect(rules_data).to_not be_nil
          expect(rules_data['id']).to eq 'blocked_ips'
          expect(rules_data['type']).to eq 'data_with_expiration'

          ip_values_data = rules_data['data']
          ip_values = ip_values_data.each.with_object([]) do |ip, acc|
            acc << ip['value']
          end

          expect(ip_values_data.size).to eq 2
          expect(ip_values).to eq(ip_denylist)
        end
      end

      context 'with user_id_denylist' do
        let(:user_id_denylist) { ['1', '2'] }

        it 'returns data information' do
          expect(data).to_not be_nil
          expect(data.size).to eq 1
          rules_data = data[0][0]

          expect(rules_data).to_not be_nil
          expect(rules_data['id']).to eq 'blocked_users'
          expect(rules_data['type']).to eq 'data_with_expiration'

          user_id_values_data = rules_data['data']
          user_id_values = user_id_values_data.each.with_object([]) do |user, acc|
            acc << user['value']
          end

          expect(user_id_values_data.size).to eq 2
          expect(user_id_values).to eq(user_id_denylist)
        end
      end

      context 'with ip_denylist and user_id_denylist' do
        let(:ip_denylist) { ['1.1.1.1', '1.1.1.2'] }
        let(:user_id_denylist) { ['1', '2'] }

        it 'returns data information' do
          expect(data).to_not be_nil
          expect(data.size).to eq 2
        end
      end
    end
  end
end
