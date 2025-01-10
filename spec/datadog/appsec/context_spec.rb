# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/context'

RSpec.describe Datadog::AppSec::Context do
  let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }
  let(:context) { described_class.new(trace, span, processor) }

  after do
    described_class.deactivate
    processor.finalize
  end

  describe '.active' do
    context 'with no active context' do
      it { expect(described_class.active).to be_nil }
    end

    context 'with an active context' do
      before { described_class.activate(context) }

      it { expect(described_class.active).to eq(context) }
    end
  end

  describe '.activate' do
    it { expect { described_class.activate(double) }.to raise_error(ArgumentError) }

    context 'with no active context' do
      it { expect { described_class.activate(context) }.to change { described_class.active }.from(nil).to(context) }
    end

    context 'with an active context' do
      before { described_class.activate(context) }

      subject(:activate_context) { described_class.activate(described_class.new(trace, span, processor)) }

      it 'raises ActiveContextError' do
        expect { activate_context }.to raise_error(Datadog::AppSec::Context::ActiveContextError)
      end

      it 'does not change the active context' do
        expect { activate_context rescue nil }.to_not(change { described_class.active })
      end
    end
  end

  describe '.deactivate' do
    context 'with no active context' do
      it 'does not change the active context' do
        expect { described_class.deactivate }.to_not(change { described_class.active })
      end
    end

    context 'with an active context' do
      before do
        described_class.activate(context)
        expect(context).to receive(:finalize).and_call_original
      end

      it 'unsets the active context' do
        expect { described_class.deactivate }.to change { described_class.active }.from(context).to(nil)
      end
    end

    context 'with error during deactivation' do
      before do
        described_class.activate(context)
        expect(context).to receive(:finalize).and_raise(RuntimeError.new('Ooops'))
      end

      it 'raises underlying exception' do
        expect { described_class.deactivate }.to raise_error(RuntimeError)
      end

      it 'unsets the active context' do
        expect { described_class.deactivate rescue nil }.to change { described_class.active }.from(context).to(nil)
      end
    end
  end
end
