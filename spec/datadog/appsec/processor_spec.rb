require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'

RSpec.describe Datadog::AppSec::Processor do
  before do
    # libddwaf is not available yet for JRuby
    # These specs could be made to pass still via mocking and stubbing, but
    # they'd require extensive mocking for little benefit
    skip 'disabled for Java' if RUBY_PLATFORM.include?('java')

    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug?).and_return true
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)

    allow(Datadog).to receive(:logger).and_return(logger)
  end

  after do
    described_class.send(:reset_active_context)
  end

  context 'self' do
    it 'detects if the WAF is unavailable' do
      hide_const('Datadog::AppSec::WAF')

      expect(described_class.libddwaf_provides_waf?).to be false
    end

    it 'detects if the WAF is available' do
      stub_const('Datadog::AppSec::WAF', Module.new)

      expect(described_class.libddwaf_provides_waf?).to be true
    end

    it 'reports via return of libddwaf loading failure' do
      allow(described_class).to receive(:require).with('libddwaf').and_raise(LoadError)

      expect(described_class.require_libddwaf).to be false
    end

    it 'reports via return of libddwaf loading success (first require)' do
      allow(described_class).to receive(:require).with('libddwaf').and_return(true)

      expect(described_class.require_libddwaf).to be true
    end

    it 'reports via return of libddwaf loading success (second require)' do
      allow(described_class).to receive(:require).with('libddwaf').and_return(false)

      expect(described_class.require_libddwaf).to be true
    end

    describe '.active_context' do
      it 'return nil if not set earlier' do
        expect(described_class.active_context).to be_nil
      end

      it 'return the previously set current context' do
        processor = described_class.new
        context = processor.new_context

        described_class.send(:active_context=, context)

        expect(described_class.active_context).to eq(context)

        context.finalize
        processor.finalize
        described_class.send(:reset_active_context)
      end

      describe '.active_context=' do
        it 'raises ArgumentError when trying to setup current context to a non Context instance' do
          expect do
            described_class.send(:active_context=, 'foo')
          end.to raise_error(ArgumentError)
        end
      end

      describe '.reset_active_context' do
        it 'sets active_context to nil' do
          processor = described_class.new
          context = processor.new_context

          described_class.send(:active_context=, context)

          expect(described_class.active_context).to eq(context)

          described_class.send(:reset_active_context)
          expect(described_class.active_context).to be_nil

          context.finalize
          processor.finalize
        end
      end
    end
  end

  describe '#load_libddwaf' do
    context 'when LoadError is raised' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_raise(LoadError)
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be false }
    end

    context 'when loaded but missing mandatory const' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        hide_const('Datadog::AppSec::WAF')
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be false }
    end

    context 'when loaded successfully' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        stub_const('Datadog::AppSec::WAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF::Error', Class.new(StandardError))
      end

      it { expect(described_class.new.send(:load_libddwaf)).to be true }
    end
  end

  describe '#load_ruleset' do
    let(:settings) { Datadog::AppSec.settings }
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

    before do
      allow(settings).to receive(:ruleset).and_return(ruleset)
    end

    context 'when ruleset is :recommended' do
      let(:ruleset) { :recommended }

      before do
        expect(Datadog::AppSec::Assets).to receive(:waf_rules).with(:recommended).and_call_original.twice
      end

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is :strict' do
      let(:ruleset) { :strict }

      before do
        expect(Datadog::AppSec::Assets).to receive(:waf_rules).with(:strict).and_call_original.twice
      end

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is :risky' do
      let(:ruleset) { :risky }

      before do
        expect(Datadog::AppSec::Assets).to receive(:waf_rules).with(:recommended).and_call_original.twice
      end

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is an existing path' do
      let(:ruleset) { "#{__dir__}/../../../lib/datadog/appsec/assets/waf_rules/recommended.json" }

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is a non existing path' do
      let(:ruleset) { '/does/not/exist' }

      it { expect(described_class.new.send(:load_ruleset, settings)).to be false }
    end

    context 'when ruleset is IO-like' do
      let(:ruleset) { StringIO.new(JSON.dump(basic_ruleset)) }

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is Ruby' do
      let(:ruleset) { basic_ruleset }

      it { expect(described_class.new.send(:load_ruleset, settings)).to be true }
    end

    context 'when ruleset is not parseable' do
      let(:ruleset) { StringIO.new('this is not json') }

      it { expect(described_class.new.send(:load_ruleset, settings)).to be false }
    end
  end

  describe '#create_waf_handle' do
    let(:ruleset) { :recommended }
    let(:settings) { Datadog::AppSec.settings }

    before do
      allow(settings).to receive(:ruleset).and_return(ruleset)
    end

    context 'when ruleset is default' do
      let(:ruleset) { :recommended }

      before do
        expect(Datadog::AppSec::Assets).to receive(:waf_rules).with(:recommended).and_call_original
      end

      it { expect(described_class.new.send(:create_waf_handle, settings)).to be true }
    end

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      it { expect(described_class.new.send(:create_waf_handle, settings)).to be false }
    end
  end

  describe '#initialize' do
    let(:ruleset) { :recommended }

    subject(:processor) { described_class.new }

    before do
      allow(Datadog::AppSec.settings).to receive(:ruleset).and_return(ruleset)
    end

    context 'when libddwaf fails to load' do
      before do
        expect(described_class).to receive(:require_libddwaf).and_return(false)

        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when libddwaf fails to provide WAF' do
      before do
        expect(described_class).to receive(:require_libddwaf).and_return(true)
        expect(described_class).to receive(:libddwaf_provides_waf?).and_return(false)

        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is a non existing path' do
      let(:ruleset) { '/does/not/exist' }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is not parseable' do
      let(:ruleset) { StringIO.new('this is not json') }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when loading static data rule configuration' do
      before do
        allow(Datadog::AppSec.settings).to receive(:ip_denylist).and_return(['192.192.1.1'])
        allow(Datadog::AppSec.settings).to receive(:user_id_denylist).and_return(['user3'])
      end

      it 'calls #update_rule_data with the right value' do
        expect_any_instance_of(described_class).to receive(:update_rule_data) do |_, args|
          expect(args.size).to eq(2)

          blocked_ips = args.find { |hash| hash['id'] == 'blocked_ips' }
          blocked_users = args.find { |hash| hash['id'] == 'blocked_users' }

          expect(blocked_ips).to_not be_nil
          expect(blocked_users).to_not be_nil
          expect(blocked_ips['type']).to eq('data_with_expiration')
          expect(blocked_users['type']).to eq('data_with_expiration')

          blocked_ips_data = blocked_ips['data']
          blocked_user_data = blocked_users['data']
          expect(blocked_ips_data.size).to eq(1)
          expect(blocked_user_data.size).to eq(1)
          expect(blocked_ips_data[0]['value']).to eq('192.192.1.1')
          expect(blocked_user_data[0]['value']).to eq('user3')
        end

        described_class.new
      end
    end

    context 'when things are OK' do
      before do
        expect(Datadog::AppSec::Assets).to receive(:waf_rules).with(:recommended).and_call_original
        expect(Datadog.logger).to_not receive(:warn)
      end

      it { is_expected.to be_ready }
    end
  end

  describe '#new_context' do
    let(:ruleset) { :recommended }

    let(:input_safe) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Ruby' } } }
    let(:input_sqli) { { 'server.request.query' => { 'q' => '1 OR 1;' } } }
    let(:input_scanner) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' } } }
    let(:input_client_ip) { { 'http.client_ip' => '1.2.3.4' } }

    let(:rule_data_client_ip) do
      [
        {
          'id' => 'blocked_ips',
          'type' => 'data_with_expiration',
          'data' => [{ 'value' => '1.2.3.4', 'expiration' => (Time.now + 1000).to_i }]
        }
      ]
    end

    let(:rule_toggle_client_ip) { { 'blk-001-001' => false } }

    let(:input) { input_scanner }

    let(:processor) { described_class.new }
    subject(:context) { processor.new_context }

    after do
      context.finalize
      processor.finalize
    end

    it { is_expected.to be_a Datadog::AppSec::Processor::Context }

    describe 'Context' do
      let(:run_count) { 1 }
      let(:timeout) { 10_000_000_000 }

      let(:runs) { Array.new(run_count) { context.run(input, timeout) } }
      let(:results) { runs }
      let(:overall_runtime) { results.reduce(0) { |a, e| a + e.total_runtime } }

      let(:run) do
        expect(runs).to have_attributes(count: 1)

        runs.first
      end

      let(:result) do
        expect(results).to have_attributes(count: 1)

        results.first
      end

      let(:rule_data) { nil }
      let(:rule_toggle) { nil }

      before do
        processor.update_rule_data(rule_data) if rule_data
        processor.toggle_rules(rule_toggle) if rule_toggle
        runs
      end

      it { expect(result.status).to eq :match }
      it { expect(context.time_ns).to be > 0 }
      it { expect(context.time_ext_ns).to be > 0 }
      it { expect(context.time_ext_ns).to be > context.time_ns }
      it { expect(context.time_ns).to eq(overall_runtime) }
      it { expect(context.timeouts).to eq 0 }

      context 'with timeout' do
        let(:timeout) { 0 }

        it { expect(result.status).to eq :ok }
        it { expect(context.time_ns).to eq 0 }
        it { expect(context.time_ext_ns).to be > 0 }
        it { expect(context.timeouts).to eq run_count }
      end

      context 'with multiple runs' do
        let(:run_count) { 10 }

        it { expect(context.time_ns).to eq(overall_runtime) }

        context 'with timeout' do
          let(:timeout) { 0 }

          it { expect(results.first.status).to eq :ok }
          it { expect(context.time_ns).to eq 0 }
          it { expect(context.time_ext_ns).to be > 0 }
          it { expect(context.timeouts).to eq run_count }
        end
      end

      describe '#run' do
        let(:matches) do
          results.reject { |r| r.status == :ok }
        end

        let(:data) do
          matches.map(&:data).flatten
        end

        let(:actions) do
          matches.map(&:actions)
        end

        context 'no attack' do
          let(:input) { input_safe }

          it { expect(matches).to eq [] }
          it { expect(data).to eq [] }
          it { expect(actions).to eq [] }
        end

        context 'one attack' do
          let(:input) { input_scanner }

          it { expect(matches).to have_attributes(count: 1) }
          it { expect(data).to have_attributes(count: 1) }
          it { expect(actions).to eq [[]] }
        end

        context 'multiple attacks per run' do
          let(:input) { input_scanner.merge(input_sqli) }

          it { expect(matches).to have_attributes(count: 1) }
          it { expect(data).to have_attributes(count: 2) }
          it { expect(actions).to eq [[]] }
        end

        context 'multiple runs' do
          context 'same attack' do
            let(:runs) do
              [
                context.run(input_scanner, timeout),
                context.run(input_scanner, timeout)
              ]
            end

            # when the same attack is detected twice in the same context, it's
            # only matching once therefore there's only one match result, thus
            # one action list returned.

            it { expect(matches).to have_attributes(count: 1) }
            it { expect(data).to have_attributes(count: 1) }
            it { expect(actions).to eq [[]] }
          end

          context 'different attacks' do
            let(:runs) do
              [
                context.run(input_sqli, timeout),
                context.run(input_scanner, timeout)
              ]
            end

            # when two attacks are detected in the same context there are two
            # match results, thus two action lists, one for each.

            it { expect(matches).to have_attributes(count: 2) }
            it { expect(data).to have_attributes(count: 2) }
            it { expect(actions).to eq [[], []] }
          end
        end

        context 'one blockable attack' do
          let(:input) { input_client_ip }
          let(:rule_data) { rule_data_client_ip }

          it { expect(matches).to have_attributes(count: 1) }
          it { expect(data).to have_attributes(count: 1) }
          it { expect(actions).to eq [['block']] }
        end

        context 'one blockable attack on a disabled rule' do
          let(:input) { input_client_ip }
          let(:rule_data) { rule_data_client_ip }
          let(:rule_toggle) { rule_toggle_client_ip }

          it { expect(matches).to have_attributes(count: 0) }
          it { expect(data).to have_attributes(count: 0) }
          it { expect(actions).to have_attributes(count: 0) }
        end
      end
    end
  end

  describe '#active_context' do
    it 'creates a new context and store in the class .active_context variable' do
      context = described_class.new.activate_context
      expect(context).to eq(described_class.active_context)
    end

    context 'when an active context already exists' do
      it 'raises AlreadyActiveContextError' do
        described_class.new.activate_context
        expect { described_class.new.activate_context }.to raise_error(described_class::AlreadyActiveContextError)
      end
    end
  end

  describe '#deactivate_context' do
    it 'finalize the active context and reset the class .active_context variable' do
      handler = described_class.new
      context = handler.activate_context

      expect(context).to receive(:finalize)
      handler.deactivate_context
      expect(described_class.active_context).to be_nil
    end

    context 'without an active_context' do
      it 'raises NoActiveContextError' do
        expect { described_class.new.deactivate_context }.to raise_error(described_class::NoActiveContextError)
      end
    end
  end
end
