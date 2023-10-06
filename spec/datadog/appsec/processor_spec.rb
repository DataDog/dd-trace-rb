# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'
require 'datadog/appsec/processor/rule_loader'
require 'datadog/appsec/processor/rule_merger'

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

  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended) }

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
  end

  describe '#load_libddwaf' do
    context 'when LoadError is raised' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_raise(LoadError)
      end

      it { expect(described_class.new(ruleset: ruleset).send(:load_libddwaf)).to be false }
    end

    context 'when loaded but missing mandatory const' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        hide_const('Datadog::AppSec::WAF')
      end

      it { expect(described_class.new(ruleset: ruleset).send(:load_libddwaf)).to be false }
    end

    context 'when loaded successfully' do
      before do
        allow(Object).to receive(:require).with('libddwaf').and_return(true)
        stub_const('Datadog::AppSec::WAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF::Error', Class.new(StandardError))
      end

      it { expect(described_class.new(ruleset: ruleset).send(:load_libddwaf)).to be true }
    end
  end

  describe '#initialize' do
    subject(:processor) { described_class.new(ruleset: ruleset) }

    context 'when valid ruleset' do
      it { is_expected.to be_ready }
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

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      before do
        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end
  end
end

RSpec.describe Datadog::AppSec::Processor::Context do
  let(:ruleset) do
    rules = Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended)
    Datadog::AppSec::Processor::RuleMerger.merge(rules: [rules])
  end

  let(:input_safe) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Ruby' } } }
  let(:input_sqli) { { 'server.request.query' => { 'q' => '1 OR 1;' } } }
  let(:input_scanner) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' } } }
  let(:input_client_ip) { { 'http.client_ip' => '1.2.3.4' } }

  let(:client_ip) { '1.2.3.4' }

  let(:input) { input_scanner }

  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset) }

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

  subject(:context) { described_class.new(processor) }

  before do
    runs
  end

  after do
    context.finalize
    processor.finalize
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

    let(:events) do
      matches.map(&:events).flatten
    end

    let(:actions) do
      matches.map(&:actions)
    end

    context 'clear key with empty values' do
      it 'removes nil values' do
        input = {
          'nil_value' => nil,
          'string_value' => 'hello'
        }
        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          {
            'string_value' => 'hello'
          },
          timeout
        ).and_call_original

        context.run(input, timeout)
      end

      it 'do not removes boolean values' do
        input = {
          'false_value' => false,
          'true_value' => true
        }
        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          input, timeout
        ).and_call_original

        context.run(input, timeout)
      end

      it 'removes empty string values' do
        input = {
          'empty_string_value' => '',
          'string_value' => 'hello'
        }
        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          {
            'string_value' => 'hello'
          },
          timeout
        ).and_call_original

        context.run(input, timeout)
      end

      it 'removes empty arrays values' do
        input = {
          'empty_array' => [],
          'non_empty_array_value' => [1, 2],
        }
        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          {
            'non_empty_array_value' => [1, 2]
          },
          timeout
        ).and_call_original

        context.run(input, timeout)
      end

      it 'removes empty hash values' do
        input = {
          'empty_hash' => {},
          'non_empty_hash_value' => { 'hello' => 'world' },
        }
        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          {
            'non_empty_hash_value' => { 'hello' => 'world' }
          },
          timeout
        ).and_call_original

        context.run(input, timeout)
      end
    end

    context 'no attack' do
      let(:input) { input_safe }

      it { expect(matches).to eq [] }
      it { expect(events).to eq [] }
      it { expect(actions).to eq [] }
    end

    context 'one attack' do
      let(:input) { input_scanner }

      it { expect(matches).to have_attributes(count: 1) }
      it { expect(events).to have_attributes(count: 1) }
      it { expect(actions).to eq [[]] }
    end

    context 'multiple attacks per run' do
      let(:input) { input_scanner.merge(input_sqli) }

      it { expect(matches).to have_attributes(count: 1) }
      it { expect(events).to have_attributes(count: 2) }
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
        it { expect(events).to have_attributes(count: 1) }
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
        it { expect(events).to have_attributes(count: 2) }
        it { expect(actions).to eq [[], []] }
      end
    end

    context 'one blockable attack' do
      let(:input) { input_client_ip }

      let(:ruleset) do
        rules = Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended)
        data = Datadog::AppSec::Processor::RuleLoader.load_data(ip_denylist: [client_ip])

        Datadog::AppSec::Processor::RuleMerger.merge(
          rules: [rules],
          data: data,
        )
      end

      it { expect(matches).to have_attributes(count: 1) }
      it { expect(events).to have_attributes(count: 1) }
      it { expect(actions).to eq [['block']] }
    end
  end

  describe '#extract_schema' do
    context 'when extrct_schema? returns true' do
      around do |example|
        ClimateControl.modify(
          'DD_EXPERIMENTAL_API_SECURITY_ENABLED' => 'true',
          'DD_API_SECURITY_REQUEST_SAMPLE_RATE' => '1'
        ) do
          example.run
        end
      end

      it 'calls the the WAF with the right arguments' do
        input = {
          'waf.context.processor' => {
            'extract-schema' => true
          }
        }

        dummy_code = 1
        dummy_result = 2

        expect(context.instance_variable_get(:@context)).to receive(:run).with(
          input,
          Datadog::AppSec::WAF::LibDDWAF::DDWAF_RUN_TIMEOUT
        ).and_return([dummy_code, dummy_result])

        expect(context.extract_schema).to eq dummy_result
      end

      it 'returns schema extraction information' do
        input = { 'server.request.query' => { 'vin' => '4Y1SL65848Z411439' } }
        context.run(input, timeout)

        results = context.extract_schema
        derivatives = results.derivatives
        expect(derivatives).to_not be_empty
        expect(derivatives['_dd.appsec.s.req.query']).to eq([{ 'vin' => [8, { 'category' => 'pii', 'type' => 'vin' }] }])
      end
    end

    context 'when extrct_schema? returns false' do
      around do |example|
        ClimateControl.modify('DD_EXPERIMENTAL_API_SECURITY_ENABLED' => 'false') do
          example.run
        end
      end

      it 'returns nil' do
        expect(context.extract_schema).to be_nil
      end
    end
  end
end
