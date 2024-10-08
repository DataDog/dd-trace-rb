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
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }

  describe '#require_libddwaf' do
    before do
      allow_any_instance_of(described_class).to receive(:libddwaf_provides_waf?).and_return(true)
      allow_any_instance_of(described_class).to receive(:create_waf_handle).and_return(true)
    end

    context 'successful' do
      it do
        allow_any_instance_of(described_class).to receive(:require).with('libddwaf')

        expect(telemetry).not_to receive(:report)

        described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(Datadog.logger).not_to have_received(:warn)
      end
    end

    context 'when LoadError is raised' do
      it do
        allow_any_instance_of(described_class).to receive(:require).with('libddwaf').and_raise(LoadError)
        expect(telemetry).to receive(:report).with(
          an_instance_of(LoadError),
          description: 'libddwaf failed to load'
        ).at_least(:once)

        described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(Datadog.logger).to have_received(:warn).with(/AppSec is disabled/)
      end
    end
  end

  describe '#libddwaf_provides_waf?' do
    before do
      allow_any_instance_of(described_class).to receive(:require_libddwaf).and_return(true)
      allow_any_instance_of(described_class).to receive(:create_waf_handle).and_return(true)
    end

    context 'when const is present' do
      it do
        stub_const('Datadog::AppSec::WAF', Module.new)

        described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(Datadog.logger).not_to have_received(:warn)
      end
    end

    context 'when loaded but missing mandatory const' do
      it do
        hide_const('Datadog::AppSec::WAF')

        described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(Datadog.logger).to have_received(:warn).with(/AppSec is disabled/)
      end
    end
  end

  describe '#create_waf_handle' do
    before do
      allow_any_instance_of(described_class).to receive(:require_libddwaf).and_return(true)
      allow_any_instance_of(described_class).to receive(:libddwaf_provides_waf?).and_return(true)
    end

    context 'when success' do
      it do
        stub_const('Datadog::AppSec::WAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF::Error', Class.new(StandardError))
        stub_const(
          'Datadog::AppSec::WAF::Handle',
          Class.new do
            def initialize(*); end

            def diagnostics
              :handle_diagnostics
            end

            def required_addresses
              [:required_addresses]
            end
          end
        )
        expect(telemetry).not_to receive(:report)

        processor = described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(processor).to be_ready
        expect(processor.diagnostics).to eq(:handle_diagnostics)
        expect(processor.addresses).to eq([:required_addresses])

        expect(Datadog.logger).not_to have_received(:warn)
      end
    end

    context 'when fail' do
      it do
        stub_const('Datadog::AppSec::WAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF', Module.new)
        stub_const(
          'Datadog::AppSec::WAF::LibDDWAF::Error',
          Class.new(StandardError) do
            def diagnostics
              :error_diagnostics
            end
          end
        )
        stub_const(
          'Datadog::AppSec::WAF::Handle',
          Class.new do
            def initialize(*)
              raise Datadog::AppSec::WAF::LibDDWAF::Error
            end

            def diagnostics
              :handle_diagnostics
            end

            def required_addresses
              []
            end
          end
        )
        expect(telemetry).to receive(:report).with(
          a_kind_of(Datadog::AppSec::WAF::LibDDWAF::Error),
          description: 'libddwaf failed to initialize'
        )

        processor = described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(processor).not_to be_ready
        expect(processor.diagnostics).to eq(:error_diagnostics)
        expect(processor.addresses).to eq([])

        expect(Datadog.logger).to have_received(:warn).with(/AppSec is disabled/)
      end

      it do
        stub_const('Datadog::AppSec::WAF', Module.new)
        stub_const('Datadog::AppSec::WAF::LibDDWAF', Module.new)
        stub_const(
          'Datadog::AppSec::WAF::LibDDWAF::Error',
          Class.new(StandardError)
        )
        stub_const(
          'Datadog::AppSec::WAF::Handle',
          Class.new do
            def initialize(*)
              raise StandardError
            end

            def diagnostics
              :handle_diagnostics
            end

            def required_addresses
              []
            end
          end
        )
        expect(telemetry).to receive(:report).with(
          a_kind_of(StandardError),
          description: 'libddwaf failed to initialize'
        )

        processor = described_class.new(ruleset: ruleset, telemetry: telemetry)

        expect(processor).not_to be_ready
        expect(processor.diagnostics).to be_nil
        expect(processor.addresses).to eq([])

        expect(Datadog.logger).to have_received(:warn).with(/AppSec is disabled/)
      end
    end
  end

  describe '#initialize' do
    subject(:processor) { described_class.new(ruleset: ruleset, telemetry: telemetry) }

    context 'when valid ruleset' do
      it { is_expected.to be_ready }
    end

    context 'when libddwaf fails to load' do
      before do
        expect(Datadog.logger).to receive(:warn)
        expect_any_instance_of(described_class).to receive(:require_libddwaf).and_return(false)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when libddwaf fails to provide WAF' do
      before do
        expect_any_instance_of(described_class).to receive(:require_libddwaf).and_return(true)
        expect_any_instance_of(described_class).to receive(:libddwaf_provides_waf?).and_return(false)

        expect(Datadog.logger).to receive(:warn)
      end

      it { is_expected.to_not be_ready }
    end

    context 'when ruleset is invalid' do
      let(:ruleset) { { 'not' => 'valid' } }

      it do
        expect(Datadog.logger).to receive(:warn)
        expect(telemetry).to receive(:report).with(
          a_kind_of(StandardError),
          description: 'libddwaf failed to initialize'
        )

        is_expected.to_not be_ready
      end
    end

    context 'when reporting errors' do
      it do
        stub_const('Datadog::AppSec::WAF::Handle', double)
        stub_const('Datadog::AppSec::WAF::LibDDWAF::Error', Class.new(StandardError))

        expect_any_instance_of(described_class).to receive(:require_libddwaf).and_return(true)
        expect_any_instance_of(described_class).to receive(:libddwaf_provides_waf?).and_return(true)

        expect(Datadog::AppSec::WAF::Handle).to receive(:new).and_raise(StandardError)
        expect(telemetry).to receive(:report).with(
          an_instance_of(StandardError),
          description: 'libddwaf failed to initialize'
        )

        expect(processor).to_not be_ready
      end

      it do
        stub_const('Datadog::AppSec::WAF::Handle', double)
        stub_const(
          'Datadog::AppSec::WAF::LibDDWAF::Error',
          Class.new(StandardError) do
            def diagnostics
              nil
            end
          end
        )

        expect_any_instance_of(described_class).to receive(:require_libddwaf).and_return(true)
        expect_any_instance_of(described_class).to receive(:libddwaf_provides_waf?).and_return(true)

        expect(Datadog::AppSec::WAF::Handle).to receive(:new).and_raise(Datadog::AppSec::WAF::LibDDWAF::Error)
        expect(telemetry).to receive(:report).with(
          an_instance_of(Datadog::AppSec::WAF::LibDDWAF::Error),
          description: 'libddwaf failed to initialize'
        )

        expect(processor).to_not be_ready
      end
    end
  end
end

RSpec.describe Datadog::AppSec::Processor::Context do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:ruleset) do
    rules = Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry)
    Datadog::AppSec::Processor::RuleMerger.merge(rules: [rules], telemetry: telemetry)
  end

  let(:input_safe) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Ruby' } } }
  let(:input_sqli) { { 'server.request.query' => { 'q' => '1 OR 1;' } } }
  let(:input_scanner) { { 'server.request.headers.no_cookies' => { 'user-agent' => 'Nessus SOAP' } } }
  let(:input_client_ip) { { 'http.client_ip' => '1.2.3.4' } }

  let(:client_ip) { '1.2.3.4' }

  let(:input) { input_scanner }

  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }

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
        rules = Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry)
        data = Datadog::AppSec::Processor::RuleLoader.load_data(ip_denylist: [client_ip])

        Datadog::AppSec::Processor::RuleMerger.merge(
          rules: [rules],
          data: data,
          telemetry: telemetry
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
