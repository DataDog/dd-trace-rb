# frozen_string_literal: true

require 'rspec'

require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/all_sampler'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/sync_writer'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'

RSpec.describe Datadog::Tracing::Component do
  describe '::build_tracer' do
    subject(:build_tracer) { described_class.build_tracer(settings, agent_settings, logger: logger) }

    let(:logger) do
      instance_double(Datadog::Core::Logger).tap do |logger|
        allow(logger).to receive(:debug)
      end
    end
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

    context 'given an instance' do
      let(:instance) { instance_double(Datadog::Tracing::Tracer) }

      before do
        expect(settings.tracing).to receive(:instance)
          .and_return(instance)
      end

      it 'uses the tracer instance' do
        expect(Datadog::Tracing::Tracer).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context 'given settings' do
      shared_examples_for 'new tracer' do
        let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
        let(:writer) { Datadog::Tracing::Writer.new(agent_settings: test_agent_settings) }
        let(:trace_flush) { be_a(Datadog::Tracing::Flush::Finished) }
        let(:sampler) do
          if defined?(super)
            super()
          else
            lambda do |sampler|
              expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
              expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
              expect(sampler.priority_sampler.rate_limiter.rate).to eq(settings.tracing.sampling.rate_limit)
              expect(sampler.priority_sampler.default_sampler).to be_a(Datadog::Tracing::Sampling::RateByServiceSampler)
            end
          end
        end
        let(:span_sampler) { be_a(Datadog::Tracing::Sampling::Span::Sampler) }
        let(:default_options) do
          {
            default_service: settings.service,
            enabled: settings.tracing.enabled,
            trace_flush: trace_flush,
            tags: settings.tags,
            sampler: sampler,
            span_sampler: span_sampler,
            writer: writer,
            logger: logger,
          }
        end

        let(:options) { defined?(super) ? super() : {} }
        let(:tracer_options) do
          default_options.merge(options).tap do |options|
            sampler = options[:sampler]
            options[:sampler] = lambda do |sampler_delegator|
              expect(sampler_delegator).to be_a(Datadog::Tracing::Component::SamplerDelegatorComponent)
              expect(sampler_delegator.sampler).to match(sampler)
            end
          end
        end
        let(:writer_options) { defined?(super) ? super() : {} }

        before do
          expect(Datadog::Tracing::Tracer).to receive(:new)
            .with(tracer_options)
            .and_return(tracer)

          allow(Datadog::Tracing::Writer).to receive(:new)
            .with(agent_settings: agent_settings, **writer_options)
            .and_return(writer)
        end

        after do
          writer.stop
        end

        it { is_expected.to be(tracer) }
      end

      shared_examples 'event publishing writer' do
        it 'subscribes to writer events' do
          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block)
              .to be(
                described_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK
              )
          end

          build_tracer
        end
      end

      shared_examples 'event publishing writer and priority sampler' do
        before do
          allow(writer.events.after_send).to receive(:subscribe)
        end

        let(:sampler_rates_callback) { -> { double('sampler rates callback') } }

        it 'subscribes to writer events' do
          expect(described_class).to receive(:writer_update_priority_sampler_rates_callback)
            .with(tracer_options[:sampler]).and_return(sampler_rates_callback)

          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block)
              .to be(
                described_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK
              )
          end

          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block).to be(sampler_rates_callback)
          end

          build_tracer
        end
      end

      context 'by default' do
        it_behaves_like 'new tracer' do
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.tracing)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {enabled: enabled} }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :env' do
        let(:env) { double('env') }

        before do
          allow(settings)
            .to receive(:env)
            .and_return(env)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {tags: {'env' => env}} }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :partial_flush :enabled' do
        let(:enabled) { true }

        before do
          allow(settings.tracing.partial_flush)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {trace_flush: be_a(Datadog::Tracing::Flush::Partial)} }
          it_behaves_like 'event publishing writer and priority sampler'
        end

        context 'with :partial_flush :min_spans_threshold' do
          let(:min_spans_threshold) { double('min_spans_threshold') }

          before do
            allow(settings.tracing.partial_flush)
              .to receive(:min_spans_threshold)
              .and_return(min_spans_threshold)
          end

          it_behaves_like 'new tracer' do
            let(:options) do
              {trace_flush: be_a(Datadog::Tracing::Flush::Partial) &
                have_attributes(min_spans_for_partial: min_spans_threshold)}
            end

            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :sampler' do
        before do
          allow(settings.tracing)
            .to receive(:sampler)
            .and_return(sampler)
        end

        let(:sampler) { double('sampler') }

        it_behaves_like 'new tracer' do
          let(:options) { {sampler: sampler} }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with sampling.rules' do
        before { allow(settings.tracing.sampling).to receive(:rules).and_return(rules) }

        context 'with rules' do
          let(:rules) { '[{"sample_rate":"0.123"}]' }

          it_behaves_like 'new tracer' do
            let(:sampler) do
              lambda do |sampler|
                expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
                expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)

                expect(sampler.priority_sampler.rules).to have(1).item
                expect(sampler.priority_sampler.rules[0].sampler.sample_rate).to eq(0.123)
              end
            end
          end
        end
      end

      context 'with sampling.span_rules' do
        before { allow(settings.tracing.sampling).to receive(:span_rules).and_return(rules) }

        context 'with rules' do
          let(:rules) { '[{"name":"foo"}]' }

          it_behaves_like 'new tracer' do
            let(:options) do
              {
                span_sampler: be_a(Datadog::Tracing::Sampling::Span::Sampler) & have_attributes(
                  rules: [
                    Datadog::Tracing::Sampling::Span::Rule.new(
                      Datadog::Tracing::Sampling::Span::Matcher.new(name_pattern: 'foo')
                    )
                  ]
                )
              }
            end
          end
        end

        context 'without rules' do
          let(:rules) { nil }

          it_behaves_like 'new tracer' do
            let(:options) { {span_sampler: be_a(Datadog::Tracing::Sampling::Span::Sampler) & have_attributes(rules: [])} }
          end
        end
      end

      context 'with :service' do
        let(:service) { double('service') }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {default_service: service} }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :tags' do
        let(:tags) do
          {
            'env' => 'tag_env',
            'version' => 'tag_version'
          }
        end

        before do
          allow(settings)
            .to receive(:tags)
            .and_return(tags)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {tags: tags} }
          it_behaves_like 'event publishing writer and priority sampler'
        end

        context 'with conflicting :env' do
          let(:env) { 'setting_env' }

          before do
            allow(settings)
              .to receive(:env)
              .and_return(env)
          end

          it_behaves_like 'new tracer' do
            let(:options) { {tags: tags.merge('env' => env)} }
            it_behaves_like 'event publishing writer and priority sampler'
          end
        end

        context 'with conflicting :version' do
          let(:version) { 'setting_version' }

          before do
            allow(settings)
              .to receive(:version)
              .and_return(version)
          end

          it_behaves_like 'new tracer' do
            let(:options) { {tags: tags.merge('version' => version)} }
            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :test_mode' do
        let(:sampler) do
          lambda do |sampler|
            expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
            expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
            expect(sampler.priority_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
          end
        end

        context ':enabled' do
          before do
            allow(settings.tracing.test_mode)
              .to receive(:enabled)
              .and_return(enabled)
          end

          context 'set to true' do
            let(:enabled) { true }

            context 'and :async' do
              context 'is set' do
                let(:writer) { Datadog::Tracing::Writer.new(agent_settings: test_agent_settings) }
                let(:writer_options) { {foo: :bar} }
                let(:writer_options_test_mode) { {foo: :baz} }

                before do
                  allow(settings.tracing.test_mode)
                    .to receive(:async)
                    .and_return(true)

                  allow(settings.tracing.test_mode)
                    .to receive(:writer_options)
                    .and_return(writer_options_test_mode)

                  expect(Datadog::Tracing::SyncWriter)
                    .not_to receive(:new)

                  expect(Datadog::Tracing::Writer)
                    .to receive(:new)
                    .with(agent_settings: agent_settings, **writer_options_test_mode)
                    .and_return(writer)
                end

                it_behaves_like 'event publishing writer'
              end

              context 'is not set' do
                let(:sync_writer) { Datadog::Tracing::SyncWriter.new(agent_settings: test_agent_settings) }

                before do
                  expect(Datadog::Tracing::SyncWriter)
                    .to receive(:new)
                    .with(agent_settings: agent_settings, **writer_options)
                    .and_return(writer)
                end

                context 'and :trace_flush' do
                  before do
                    allow(settings.tracing.test_mode)
                      .to receive(:trace_flush)
                      .and_return(trace_flush)
                  end

                  context 'is not set' do
                    let(:trace_flush) { nil }

                    it_behaves_like 'new tracer' do
                      let(:options) do
                        {
                          writer: kind_of(Datadog::Tracing::SyncWriter)
                        }
                      end
                      let(:writer) { sync_writer }

                      it_behaves_like 'event publishing writer'
                    end
                  end

                  context 'is set' do
                    let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

                    it_behaves_like 'new tracer' do
                      let(:options) do
                        {
                          trace_flush: trace_flush,
                          writer: kind_of(Datadog::Tracing::SyncWriter)
                        }
                      end
                      let(:writer) { sync_writer }

                      it_behaves_like 'event publishing writer'
                    end
                  end
                end

                context 'and :writer_options' do
                  before do
                    allow(settings.tracing.test_mode)
                      .to receive(:writer_options)
                      .and_return(writer_options)
                  end

                  context 'are set' do
                    let(:writer_options) { {transport_options: :bar} }

                    it_behaves_like 'new tracer' do
                      let(:options) do
                        {
                          writer: writer
                        }
                      end
                      let(:writer) { sync_writer }

                      it_behaves_like 'event publishing writer'
                    end
                  end
                end
              end
            end
          end
        end
      end

      context 'with :version' do
        let(:version) { double('version') }

        before do
          allow(settings)
            .to receive(:version)
            .and_return(version)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {tags: {'version' => version}} }
        end
      end

      context 'with :writer' do
        let(:writer) { instance_double(Datadog::Tracing::Writer) }

        before do
          allow(settings.tracing)
            .to receive(:writer)
            .and_return(writer)

          expect(Datadog::Tracing::Writer).to_not receive(:new)
        end

        it_behaves_like 'new tracer' do
          let(:options) { {writer: writer} }
        end

        context 'that publishes events' do
          it_behaves_like 'new tracer' do
            let(:options) { {writer: writer} }
            let(:writer) { Datadog::Tracing::Writer.new(agent_settings: test_agent_settings) }
            after { writer.stop }

            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :writer_options' do
        let(:writer_options) { {custom_option: :custom_value} }

        it_behaves_like 'new tracer' do
          before do
            expect(settings.tracing)
              .to receive(:writer_options)
              .and_return(writer_options)
          end
        end

        context 'and :writer' do
          let(:writer) { double('writer') }

          before do
            allow(settings.tracing)
              .to receive(:writer)
              .and_return(writer)
          end

          it_behaves_like 'new tracer' do
            # Ignores the writer options in favor of the writer
            let(:options) { {writer: writer} }
          end
        end
      end
    end
  end

  describe 'writer event callbacks' do
    describe Datadog::Tracing::Component::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK do
      subject(:call) { described_class.call(writer, responses) }
      let(:writer) { double('writer') }
      let(:responses) { [double('response')] }

      before do
        Datadog::Tracing::Component::WRITER_RECORD_ENVIRONMENT_INFORMATION_ONLY_ONCE.send(:reset_ran_once_state_for_tests)
      end

      it 'invokes the environment logger with responses' do
        expect(Datadog::Tracing::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!).with(responses: responses)
        call
      end

      it 'invokes the environment logger only once' do
        expect(Datadog::Tracing::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!).once

        described_class.call(writer, responses)
        described_class.call(writer, responses)
      end
    end

    describe '.writer_update_priority_sampler_rates_callback' do
      subject(:call) do
        described_class.writer_update_priority_sampler_rates_callback(sampler).call(writer, responses)
      end

      let(:sampler) { double('sampler') }
      let(:writer) { double('writer') }
      let(:responses) do
        [
          double('first response'),
          double('last response', internal_error?: internal_error, service_rates: service_rates),
        ]
      end

      let(:service_rates) { nil }

      context 'with a successful response' do
        let(:internal_error) { false }

        context 'with service rates returned by response' do
          let(:service_rates) { double('service rates') }

          it 'updates sampler with service rates and set decision to AGENT_RATE' do
            expect(sampler).to receive(:update).with(service_rates, decision: '-1')
            call
          end
        end

        context 'without service rates returned by response' do
          it 'does not update sampler' do
            expect(sampler).to_not receive(:update)
            call
          end
        end
      end

      context 'with an internal error response' do
        let(:internal_error) { true }

        it 'does not update sampler' do
          expect(sampler).to_not receive(:update)
          call
        end
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Component::SamplerDelegatorComponent do
  let(:delegator) { described_class.new(old_sampler) }
  let(:old_sampler) { double('initial') }
  let(:new_sampler) { double('new') }

  let(:trace) { double('trace') }

  it 'changes instance on sampler=' do
    expect { delegator.sampler = new_sampler }.to change { delegator.sampler }.from(old_sampler).to(new_sampler)
  end

  it 'delegates #sample! to the internal sampler' do
    expect(old_sampler).to receive(:sample!).with(trace)
    delegator.sample!(trace)
  end

  it 'delegates #update to the internal sampler' do
    expect(old_sampler).to receive(:update).with(1, 2, a: 3, b: 4)
    delegator.update(1, 2, a: 3, b: 4)
  end

  it "does not delegate #update when internal sampler doesn't support it" do
    delegator.update(1, 2, a: 3, b: 4)
  end
end
