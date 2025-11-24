# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature'

RSpec.describe Datadog::OpenFeature do
  describe '.enabled?' do
    context 'when OpenFeature is disabled' do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(false) }
    end

    context 'when OpenFeature is enabled' do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = true }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(true) }
    end
  end

  describe '.engine' do
    context 'when component is not available' do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.engine).to be_nil }
    end

    context 'when component and remote configuration are available' do
      before do
        # NOTE: To avoid the use of doubles or partial doubles outside of the per-test lifecycle
        #       we have to split around hook into before/after.
        stub_const('Datadog::Core::LIBDATADOG_API_FAILURE', nil)

        Datadog.configure do |c|
          c.remote.enabled = true
          c.open_feature.enabled = true
        end
      end

      after { Datadog.configuration.reset! }

      it { expect(described_class.engine).to be_a(Datadog::OpenFeature::EvaluationEngine) }
    end

    context 'when component is available and remote configuration is not available' do
      around do |example|
        Datadog.configure do |c|
          c.remote.enabled = false
          c.open_feature.enabled = true
        end

        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.engine).to be_nil }
    end
  end
end
