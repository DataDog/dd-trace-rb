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

    context 'when component is available' do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = true }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.engine).to be_a(Datadog::OpenFeature::EvaluationEngine) }
    end
  end
end
