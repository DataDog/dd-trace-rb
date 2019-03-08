require 'ddtrace/ext/analytics'

RSpec.shared_examples_for 'analytics for integration' do
  context 'when not configured' do
    it 'is not included in the tags' do
      expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
    end
  end

  context 'when configured by environment variable' do
    context 'and explicitly enabled' do
      around do |example|
        ClimateControl.modify(analytics_enabled_var => 'true') do
          example.run
        end
      end

      context 'and sample rate isn\'t set' do
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0) }
      end

      context 'and sample rate is set' do
        let(:analytics_sample_rate) { 0.5 }
        around do |example|
          ClimateControl.modify(analytics_sample_rate_var => analytics_sample_rate.to_s) do
            example.run
          end
        end

        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(analytics_sample_rate) }
      end
    end

    context 'and explicitly disabled' do
      around do |example|
        ClimateControl.modify(analytics_enabled_var => 'false') do
          example.run
        end
      end

      context 'and sample rate isn\'t set' do
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
      end

      context 'and sample rate is set' do
        let(:analytics_sample_rate) { 0.5 }
        around do |example|
          ClimateControl.modify(analytics_sample_rate_var => analytics_sample_rate.to_s) do
            example.run
          end
        end

        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
      end
    end
  end

  context 'when configured by configuration options' do
    context 'and explicitly enabled' do
      let(:configuration_options) { super().merge(analytics_enabled: true) }

      context 'and sample rate isn\'t set' do
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0) }
      end

      context 'and sample rate is set' do
        let(:configuration_options) { super().merge(analytics_sample_rate: analytics_sample_rate) }
        let(:analytics_sample_rate) { 0.5 }
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(analytics_sample_rate) }
      end
    end

    context 'and explicitly disabled' do
      let(:configuration_options) { super().merge(analytics_enabled: false) }

      context 'and sample rate isn\'t set' do
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
      end

      context 'and sample rate is set' do
        let(:configuration_options) { super().merge(analytics_sample_rate: analytics_sample_rate) }
        let(:analytics_sample_rate) { 0.5 }
        it { expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
      end
    end
  end
end
