# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/processor'
require 'datadog/appsec/processor/rule_loader'

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

  describe '#new_context' do
    let(:processor) { described_class.new(ruleset: ruleset, telemetry: telemetry) }

    it { expect(processor.new_context).to be_instance_of(described_class::Context) }
  end
end
