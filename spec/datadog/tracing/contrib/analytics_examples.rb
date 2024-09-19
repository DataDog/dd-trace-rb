require 'datadog/tracing/metadata/ext'

RSpec.shared_examples_for 'analytics for integration' do |options = { ignore_global_flag: true }|
  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    without_warnings { Datadog.configuration.reset! }
    example.run
    without_warnings { Datadog.configuration.reset! }
  end

  context 'when not configured' do
    context 'and the global flag is not set' do
      it 'is not included in the tags' do
        expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
      end
    end

    context 'and the global flag is enabled' do
      around do |example|
        ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'true') do
          example.run
        end
      end

      # Most integrations ignore the global flag by default,
      # because they aren't considered "key" integrations.
      # These integrations will not expect it to be set, despite the global flag.
      if options[:ignore_global_flag]
        it 'is not included in the tags' do
          expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
        end
      else
        it 'is included in the tags' do
          expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0)
        end
      end
    end

    context 'and the global flag is disabled' do
      around do |example|
        ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'false') do
          example.run
        end
      end

      it 'is not included in the tags' do
        expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil
      end
    end
  end

  context 'when configured by environment variable' do
    context 'and explicitly enabled' do
      around do |example|
        ClimateControl.modify(analytics_enabled_var => 'true') do
          example.run
        end
      end

      shared_examples_for 'sample rate value' do
        context 'isn\'t set' do
          it { expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0) }
        end

        context 'is set' do
          let(:analytics_sample_rate) { 0.5 }

          around do |example|
            ClimateControl.modify(analytics_sample_rate_var => analytics_sample_rate.to_s) do
              example.run
            end
          end

          it do
            expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE))
              .to eq(analytics_sample_rate)
          end
        end
      end

      context 'and global flag' do
        context 'is not set' do
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly enabled' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'true'
            ) do
              example.run
            end
          end

          it_behaves_like 'sample rate value'
        end

        context 'is explicitly disabled' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'false'
            ) do
              example.run
            end
          end

          it_behaves_like 'sample rate value'
        end
      end
    end

    context 'and explicitly disabled' do
      around do |example|
        ClimateControl.modify(analytics_enabled_var => 'false') do
          example.run
        end
      end

      shared_examples_for 'sample rate value' do
        context 'isn\'t set' do
          it { expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
        end

        context 'is set' do
          let(:analytics_sample_rate) { 0.5 }

          around do |example|
            ClimateControl.modify(analytics_sample_rate_var => analytics_sample_rate.to_s) do
              example.run
            end
          end

          it { expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
        end
      end

      context 'and global flag' do
        context 'is not set' do
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly enabled' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'true'
            ) do
              example.run
            end
          end

          it_behaves_like 'sample rate value'
        end

        context 'is explicitly disabled' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => 'false'
            ) do
              example.run
            end
          end

          it_behaves_like 'sample rate value'
        end
      end
    end
  end

  shared_context 'analytics setting' do |analytics_enabled|
    let(:analytics_enabled) { defined?(super) ? super() : analytics_enabled }

    before { Datadog.configuration.tracing.analytics.enabled = analytics_enabled }

    after { without_warnings { Datadog.configuration.reset! } }
  end

  context 'when configured by configuration options' do
    context 'and explicitly enabled' do
      let(:configuration_options) { super().merge(analytics_enabled: true) }

      shared_examples_for 'sample rate value' do
        context 'isn\'t set' do
          it do
            expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE))
              .to eq(1.0)
          end
        end

        context 'is set' do
          let(:configuration_options) { super().merge(analytics_sample_rate: analytics_sample_rate) }
          let(:analytics_sample_rate) { 0.5 }

          it do
            expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE))
              .to eq(analytics_sample_rate)
          end
        end
      end

      context 'and global flag' do
        context 'is not set' do
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly enabled' do
          include_context 'analytics setting', true
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly disabled' do
          include_context 'analytics setting', false
          it_behaves_like 'sample rate value'
        end
      end
    end

    context 'and explicitly disabled' do
      let(:configuration_options) { super().merge(analytics_enabled: false) }

      shared_examples_for 'sample rate value' do
        context 'isn\'t set' do
          it { expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
        end

        context 'is set' do
          let(:configuration_options) { super().merge(analytics_sample_rate: analytics_sample_rate) }
          let(:analytics_sample_rate) { 0.5 }

          it { expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE)).to be nil }
        end
      end

      context 'and global flag' do
        context 'is not set' do
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly enabled' do
          include_context 'analytics setting', true
          it_behaves_like 'sample rate value'
        end

        context 'is explicitly disabled' do
          include_context 'analytics setting', false
          it_behaves_like 'sample rate value'
        end
      end
    end
  end
end

RSpec.shared_examples_for 'measured span for integration' do |expect_active = true|
  if expect_active
    it "sets #{Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED} on the span" do
      expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED)).to eq 1.0
    end
  else
    it "does not set #{Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED} on the span" do
      expect(span.get_metric(Datadog::Tracing::Metadata::Ext::Analytics::TAG_MEASURED)).to be nil
    end
  end
end
