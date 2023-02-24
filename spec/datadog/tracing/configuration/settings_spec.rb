require 'spec_helper'

require 'securerandom'

require 'datadog/core/configuration/settings'
require 'datadog/tracing/configuration/ext'
require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'

RSpec.describe Datadog::Tracing::Configuration::Settings do
  # TODO: Core::Configuration::Settings directly extends Tracing::Configuration::Settings
  #       In the future, have tracing add this behavior itself. For now,
  #       just use the core settings class to drive the tests.
  subject(:settings) { Datadog::Core::Configuration::Settings.new(options) }

  let(:options) { {} }

  describe '#tracing' do
    describe '#analytics' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.analytics.enabled }

        context "when #{Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED}" do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => environment
            ) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be nil }
          end

          context 'is defined' do
            let(:environment) { 'true' }

            it { is_expected.to be true }
          end
        end
      end

      describe '#enabled=' do
        after { settings.runtime_metrics.reset! }

        it 'changes the #enabled setting' do
          expect { settings.tracing.analytics.enabled = true }
            .to change { settings.tracing.analytics.enabled }
            .from(nil)
            .to(true)
        end
      end
    end

    describe '#distributed_tracing' do
      around do |example|
        ClimateControl.modify(var_name => var_value) do
          example.run
        end
      end

      describe '#propagation_extract_style' do
        subject(:propagation_extract_style) { settings.tracing.distributed_tracing.propagation_extract_style }

        context 'when DD_TRACE_PROPAGATION_STYLE_EXTRACT' do
          let(:var_name) { 'DD_TRACE_PROPAGATION_STYLE_EXTRACT' }

          context 'is not defined' do
            let(:var_value) { nil }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end

          context 'is defined' do
            let(:var_value) { 'b3multi,b3' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end

          context 'is set to deprecated style names' do
            let(:var_value) { 'B3,B3 single header' }

            it 'translates to new names' do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end
        end

        context 'with deprecated DD_PROPAGATION_STYLE_EXTRACT' do
          let(:var_name) { 'DD_PROPAGATION_STYLE_EXTRACT' }

          context 'is defined' do
            let(:var_value) { 'b3multi,b3' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end

            include_examples 'records deprecated action', 'DD_PROPAGATION_STYLE_EXTRACT environment variable is deprecated'
          end
        end
      end

      describe '#propagation_inject_style' do
        subject(:propagation_inject_style) { settings.tracing.distributed_tracing.propagation_inject_style }

        context 'with DD_TRACE_PROPAGATION_STYLE_INJECT' do
          let(:var_name) { 'DD_TRACE_PROPAGATION_STYLE_INJECT' }

          context 'is not defined' do
            let(:var_value) { nil }

            it { is_expected.to eq([Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG]) }
          end

          context 'is defined' do
            let(:var_value) { 'Datadog,b3' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end

          context 'is set to deprecated style names' do
            let(:var_value) { 'B3,B3 single header' }

            it 'translates to new names' do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end
        end

        context 'with deprecated DD_PROPAGATION_STYLE_INJECT' do
          let(:var_name) { 'DD_PROPAGATION_STYLE_INJECT' }

          context 'is defined' do
            let(:var_value) { 'Datadog,b3' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end

            include_examples 'records deprecated action', 'DD_PROPAGATION_STYLE_INJECT environment variable is deprecated'
          end
        end
      end

      describe '#propagation_style' do
        subject(:propagation_style) { settings.tracing.distributed_tracing.propagation_style }

        def propagation_extract_style
          settings.tracing.distributed_tracing.propagation_extract_style
        end

        def propagation_inject_style
          settings.tracing.distributed_tracing.propagation_inject_style
        end

        context 'with DD_TRACE_PROPAGATION_STYLE' do
          let(:var_name) { 'DD_TRACE_PROPAGATION_STYLE' }

          context 'is not defined' do
            let(:var_value) { nil }

            it { is_expected.to be_nil }

            it 'does not change propagation_extract_style' do
              expect { propagation_style }.to_not change { propagation_extract_style }
                .from(%w[Datadog b3multi b3])
            end

            it 'does not change propagation_inject_style' do
              expect { propagation_style }.to_not change { propagation_inject_style }.from(['Datadog'])
            end
          end

          context 'is defined' do
            let(:var_value) { 'Datadog,b3' }

            it { is_expected.to contain_exactly('Datadog', 'b3') }

            it 'sets propagation_extract_style' do
              expect { propagation_style }.to change { propagation_extract_style }
                .from(%w[Datadog b3multi b3]).to(%w[Datadog b3])
            end

            it 'sets propagation_inject_style' do
              expect { propagation_style }.to change { propagation_inject_style }.from(['Datadog']).to(%w[Datadog b3])
            end
          end
        end
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.tracing.enabled }

      it { is_expected.to be true }

      context "when #{Datadog::Tracing::Configuration::Ext::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Tracing::Configuration::Ext::ENV_ENABLED => enable) do
            example.run
          end
        end

        context 'is not defined' do
          let(:enable) { nil }

          it { is_expected.to be true }
        end

        context 'is set to true' do
          let(:enable) { 'true' }

          it { is_expected.to be true }
        end

        context 'is set to false' do
          let(:enable) { 'false' }

          it { is_expected.to be false }
        end
      end
    end

    describe '#enabled=' do
      it 'updates the #enabled setting' do
        expect { settings.tracing.enabled = false }
          .to change { settings.tracing.enabled }
          .from(true)
          .to(false)
      end
    end

    describe '#instance' do
      subject(:instance) { settings.tracing.instance }

      it { is_expected.to be nil }
    end

    describe '#instance=' do
      let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

      it 'updates the #instance setting' do
        expect { settings.tracing.instance = tracer }
          .to change { settings.tracing.instance }
          .from(nil)
          .to(tracer)
      end
    end

    describe '#log_injection' do
      subject(:log_injection) { settings.tracing.log_injection }

      context "when #{Datadog::Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED}" do
        around do |example|
          ClimateControl.modify(
            Datadog::Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED => log_injection_env
          ) do
            example.run
          end
        end

        context 'is not defined' do
          let(:log_injection_env) { nil }

          it { is_expected.to be(true) }
        end

        context 'is defined' do
          let(:log_injection_env) { 'false' }

          it { is_expected.to be(false) }
        end
      end
    end

    describe '#partial_flush' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.partial_flush.enabled }

        it { is_expected.to be false }
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.tracing.partial_flush.enabled = true }
            .to change { settings.tracing.partial_flush.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#min_spans_threshold' do
        subject(:min_spans_threshold) { settings.tracing.partial_flush.min_spans_threshold }

        it { is_expected.to eq(500) }
      end

      describe '#min_spans_threshold=' do
        let(:value) { 1234 }

        it 'updates the #min_spans_before_partial_flush setting' do
          expect { settings.tracing.partial_flush.min_spans_threshold = value }
            .to change { settings.tracing.partial_flush.min_spans_threshold }
            .from(500)
            .to(value)
        end
      end
    end

    describe '#priority_sampling' do
      subject(:priority_sampling) { settings.tracing.priority_sampling }

      it { is_expected.to be nil }
    end

    describe '#priority_sampling=' do
      it 'updates the #priority_sampling setting' do
        expect { settings.tracing.priority_sampling = true }
          .to change { settings.tracing.priority_sampling }
          .from(nil)
          .to(true)
      end
    end

    describe '#report_hostname' do
      subject(:report_hostname) { settings.tracing.report_hostname }

      context "when #{Datadog::Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME}" do
        around do |example|
          ClimateControl.modify(Datadog::Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        context 'is defined' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#report_hostname=' do
      it 'changes the #report_hostname setting' do
        expect { settings.tracing.report_hostname = true }
          .to change { settings.tracing.report_hostname }
          .from(false)
          .to(true)
      end
    end

    describe '#sampler' do
      subject(:sampler) { settings.tracing.sampler }

      it { is_expected.to be nil }
    end

    describe '#sampler=' do
      let(:sampler) { instance_double(Datadog::Tracing::Sampling::PrioritySampler) }

      it 'updates the #sampler setting' do
        expect { settings.tracing.sampler = sampler }
          .to change { settings.tracing.sampler }
          .from(nil)
          .to(sampler)
      end
    end

    describe '#sampling' do
      describe '#rate_limit' do
        subject(:rate_limit) { settings.tracing.sampling.rate_limit }

        context 'default' do
          it { is_expected.to eq(100) }
        end

        context 'when ENV is provided' do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Sampling::ENV_RATE_LIMIT => '20.0') do
              example.run
            end
          end

          it { is_expected.to eq(20.0) }
        end
      end

      describe '#default_rate' do
        subject(:default_rate) { settings.tracing.sampling.default_rate }

        context 'default' do
          it { is_expected.to be nil }
        end

        context 'when ENV is provided' do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Sampling::ENV_SAMPLE_RATE => '0.5') do
              example.run
            end
          end

          it { is_expected.to eq(0.5) }
        end
      end

      describe '#span_rules' do
        subject(:rules) { settings.tracing.sampling.span_rules }

        context 'default' do
          it { is_expected.to be nil }
        end

        context 'when DD_SPAN_SAMPLING_RULES is provided' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES => '{}'
            ) do
              example.run
            end
          end

          it { is_expected.to eq('{}') }

          context 'and DD_SPAN_SAMPLING_RULES_FILE is also provided' do
            around do |example|
              ClimateControl.modify(
                Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE => 'path'
              ) do
                example.run
              end
            end

            it 'emits a conflict warning and returns DD_SPAN_SAMPLING_RULES' do
              expect(Datadog.logger).to receive(:warn).with(include('configuration conflict'))
              is_expected.to eq('{}')
            end
          end
        end

        context 'when DD_SPAN_SAMPLING_RULES_FILE is provided' do
          around do |example|
            Tempfile.open('DD_SPAN_SAMPLING_RULES_FILE') do |f|
              f.write('{from:"file"}')
              f.flush

              ClimateControl.modify(
                Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE => f.path
              ) do
                example.run
              end
            end
          end

          it { is_expected.to eq('{from:"file"}') }
        end
      end
    end

    describe '#test_mode' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.test_mode.enabled }

        it { is_expected.to be false }

        context "when #{Datadog::Tracing::Configuration::Ext::Test::ENV_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Test::ENV_MODE_ENABLED => enable) do
              example.run
            end
          end

          context 'is not defined' do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context 'is set to true' do
            let(:enable) { 'true' }

            it { is_expected.to be true }
          end

          context 'is set to false' do
            let(:enable) { 'false' }

            it { is_expected.to be false }
          end
        end
      end

      describe '#trace_flush' do
        subject(:trace_flush) { settings.tracing.test_mode.trace_flush }

        context 'default' do
          it { is_expected.to be nil }
        end
      end

      describe '#trace_flush=' do
        let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

        it 'updates the #trace_flush setting' do
          expect { settings.tracing.test_mode.trace_flush = trace_flush }
            .to change { settings.tracing.test_mode.trace_flush }
            .from(nil)
            .to(trace_flush)
        end
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.tracing.test_mode.enabled = true }
            .to change { settings.tracing.test_mode.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#writer_options' do
        subject(:writer_options) { settings.tracing.test_mode.writer_options }

        it { is_expected.to eq({}) }

        context 'when modified' do
          it 'does not modify the default by reference' do
            settings.tracing.test_mode.writer_options[:foo] = :bar
            expect(settings.tracing.test_mode.writer_options).to_not be_empty
            expect(settings.tracing.test_mode.options[:writer_options].default_value).to be_empty
          end
        end
      end

      describe '#writer_options=' do
        let(:options) { { priority_sampling: true } }

        it 'updates the #writer_options setting' do
          expect { settings.tracing.test_mode.writer_options = options }
            .to change { settings.tracing.test_mode.writer_options }
            .from({})
            .to(options)
        end
      end
    end

    describe '#transport_options' do
      subject(:transport_options) { settings.tracing.transport_options }

      it { is_expected.to be nil }
    end

    describe '#transport_options=' do
      let(:config_proc) { proc { |t| t.adapter :test } }

      it 'updates the #transport_options setting' do
        expect { settings.tracing.transport_options = config_proc }
          .to change { settings.tracing.transport_options }
          .from(nil)
          .to(config_proc)
      end
    end

    describe '#writer' do
      subject(:writer) { settings.tracing.writer }

      it { is_expected.to be nil }
    end

    describe '#writer=' do
      let(:writer) { instance_double(Datadog::Tracing::Writer) }

      it 'updates the #writer setting' do
        expect { settings.tracing.writer = writer }
          .to change { settings.tracing.writer }
          .from(nil)
          .to(writer)
      end
    end

    describe '#writer_options' do
      subject(:writer_options) { settings.tracing.writer_options }

      it { is_expected.to eq({}) }

      context 'when modified' do
        it 'does not modify the default by reference' do
          settings.tracing.writer_options[:foo] = :bar
          expect(settings.tracing.writer_options).to_not be_empty
          expect(settings.tracing.options[:writer_options].default_value).to be_empty
        end
      end
    end

    describe '#writer_options=' do
      let(:options) { { priority_sampling: true } }

      it 'updates the #writer_options setting' do
        expect { settings.tracing.writer_options = options }
          .to change { settings.tracing.writer_options }
          .from({})
          .to(options)
      end
    end

    describe '#x_datadog_tags_max_length' do
      subject { settings.tracing.x_datadog_tags_max_length }

      context "when #{Datadog::Tracing::Configuration::Ext::Distributed::ENV_X_DATADOG_TAGS_MAX_LENGTH}" do
        around do |example|
          ClimateControl.modify(
            Datadog::Tracing::Configuration::Ext::Distributed::ENV_X_DATADOG_TAGS_MAX_LENGTH => env_var
          ) do
            example.run
          end
        end

        context 'is not defined' do
          let(:env_var) { nil }

          it { is_expected.to eq(512) }
        end

        context 'is defined' do
          let(:env_var) { '123' }

          it { is_expected.to eq(123) }
        end
      end
    end

    describe '#x_datadog_tags_max_length=' do
      it 'updates the #x_datadog_tags_max_length setting' do
        expect { settings.tracing.x_datadog_tags_max_length = 123 }
          .to change { settings.tracing.x_datadog_tags_max_length }
          .from(512)
          .to(123)
      end
    end
  end
end
