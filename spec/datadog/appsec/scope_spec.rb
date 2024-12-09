# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/scope'

RSpec.describe Datadog::AppSec::Scope do
  let(:trace) { double }
  let(:span) { double }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:ruleset) { Datadog::AppSec::Processor::RuleLoader.load_rules(ruleset: :recommended, telemetry: telemetry) }
  let(:processor) { Datadog::AppSec::Processor.new(ruleset: ruleset, telemetry: telemetry) }

  after do
    described_class.send(:reset_active_scope)
    processor.finalize
  end

  describe '.activate_scope' do
    context 'with no active scope' do
      subject(:activate_scope) { described_class.activate_scope(trace, span, processor) }

      it 'returns a new scope' do
        expect(activate_scope).to be_a described_class
      end

      it 'sets the active scope' do
        expect { activate_scope }.to change { described_class.active_scope }.from(nil).to be_a described_class
      end
    end

    context 'with an active scope' do
      before do
        described_class.activate_scope(trace, span, processor)
      end

      subject(:activate_scope) { described_class.activate_scope(trace, span, processor) }

      it 'raises ActiveScopeError' do
        expect { activate_scope }.to raise_error Datadog::AppSec::Scope::ActiveScopeError
      end

      it 'does not change the active scope' do
        expect { activate_scope rescue nil }.to_not(change { described_class.active_scope })
      end
    end
  end

  describe '.deactivate_scope' do
    context 'with no active scope' do
      subject(:deactivate_scope) { described_class.deactivate_scope }

      it 'raises ActiveScopeError' do
        expect { deactivate_scope }.to raise_error Datadog::AppSec::Scope::InactiveScopeError
      end

      it 'does not change the active scope' do
        expect { deactivate_scope rescue nil }.to_not(change { described_class.active_scope })
      end
    end

    context 'with an active scope' do
      let(:active_scope) { described_class.active_scope }

      subject(:deactivate_scope) { described_class.deactivate_scope }

      before do
        allow(described_class).to receive(:new).and_call_original

        described_class.activate_scope(trace, span, processor)

        expect(active_scope).to receive(:finalize).and_call_original
      end

      it 'unsets the active scope' do
        expect { deactivate_scope }.to change { described_class.active_scope }.from(active_scope).to nil
      end
    end
  end

  describe '.active_scope' do
    subject(:active_scope) { described_class.active_scope }

    context 'with no active scope' do
      it { is_expected.to be_nil }
    end

    context 'with an active scope' do
      before do
        described_class.activate_scope(trace, span, processor)
      end

      it { is_expected.to be_a described_class }
    end
  end
end
