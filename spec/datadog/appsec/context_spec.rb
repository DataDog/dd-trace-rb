# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/context'

RSpec.describe Datadog::AppSec::Context do
  let(:trace) { double }
  let(:span) { double }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }

  after do
    described_class.send(:reset_active_context)
    processor.finalize
  end

  describe '.activate_context' do
    context 'with no active context' do
      subject(:activate_context) { described_class.activate_context(trace, span, processor) }

      it 'returns a new context' do
        expect(activate_context).to be_a described_class
      end

      it 'sets the active context' do
        expect { activate_context }.to change { described_class.active_context }.from(nil).to be_a described_class
      end
    end

    context 'with an active context' do
      before do
        described_class.activate_context(trace, span, processor)
      end

      subject(:activate_context) { described_class.activate_context(trace, span, processor) }

      it 'raises ActiveScopeError' do
        expect { activate_context }.to raise_error Datadog::AppSec::Context::ActiveScopeError
      end

      it 'does not change the active context' do
        expect { activate_context rescue nil }.to_not(change { described_class.active_context })
      end
    end
  end

  describe '.deactivate_context' do
    context 'with no active context' do
      subject(:deactivate_context) { described_class.deactivate_context }

      it 'raises ActiveContextError' do
        expect { deactivate_context }.to raise_error Datadog::AppSec::Context::InactiveScopeError
      end

      it 'does not change the active context' do
        expect { deactivate_context rescue nil }.to_not(change { described_class.active_context })
      end
    end

    context 'with an active context' do
      let(:active_context) { described_class.active_context }
      subject(:deactivate_context) { described_class.deactivate_context }

      before do
        allow(described_class).to receive(:new).and_call_original

        described_class.activate_context(trace, span, processor)

        expect(active_context).to receive(:finalize).and_call_original
      end

      it 'unsets the active context' do
        expect { deactivate_context }.to change { described_class.active_context }.from(active_context).to nil
      end
    end
  end

  describe '.active_context' do
    subject(:active_context) { described_class.active_context }

    context 'with no active context' do
      it { is_expected.to be_nil }
    end

    context 'with an active context' do
      before { described_class.activate_context(trace, span, processor) }

      it { is_expected.to be_a described_class }
    end
  end
end
