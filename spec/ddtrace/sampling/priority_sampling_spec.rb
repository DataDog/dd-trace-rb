require 'spec_helper'

require 'ddtrace/transport/traces'
require 'ddtrace/sampling/priority_sampling'

RSpec.describe Datadog::Sampling::PrioritySampling do
  describe '::activate!' do
    subject(:activate!) { described_class.activate! }

    shared_examples_for 'priority sampling activation' do
      before do
        allow(tracer).to receive(:configure)
        allow(trace_writer.flush_completed).to receive(:subscribe)
      end

      context 'when the tracer sampler' do
        before do
          allow(tracer.sampler).to receive(:is_a?)
            .with(Datadog::PrioritySampler)
            .and_return(priority_sampler?)
        end

        context 'is a priority sampler' do
          let(:priority_sampler?) { true }

          it 'does not configure the tracer with a new sampler' do
            activate!
            expect(tracer).to_not have_received(:configure)
          end
        end

        context 'is not a priority sampler' do
          let(:priority_sampler?) { false }

          it 'configures the tracer with a new sampler' do
            activate!

            expect(tracer).to have_received(:configure) do |options|
              expect(options).to include(:sampler)
              expect(options[:sampler]).to be_a_kind_of(Datadog::PrioritySampler)
              expect(options[:sampler]).to have_attributes(
                pre_sampler: tracer.sampler,
                priority_sampler: kind_of(Datadog::Sampling::RuleSampler)
              )
            end
          end
        end
      end

      context 'subscribes to :flush_completed' do
        before do
          allow(tracer).to receive(:configure) do |options|
            # Stub sampler after configuration was meant to occur
            # So :flush_completed event can update like expected.
            allow(tracer).to receive(:sampler).and_return(options[:sampler])
          end
        end

        it 'as :priority_sampling' do
          activate!

          expect(trace_writer.flush_completed).to have_received(:subscribe) do |name|
            expect(name).to be(:priority_sampling)
          end
        end

        context 'with a handler which given responses' do
          let(:responses) do
            [
              instance_double(
                Datadog::Transport::Traces::Response,
                service_rates: service_rates
              )
            ]
          end

          let(:service_rates) { {} }

          context 'that have #service_rates' do
            it 'updates the priority sampler' do
              activate!

              expect(trace_writer.flush_completed).to have_received(:subscribe) do |_name, &block|
                expect(tracer.sampler).to receive(:update).with(service_rates)
                block.call(responses)
              end
            end
          end

          context 'that don\'t have #service_rates' do
            let(:responses) { [instance_double(Datadog::Transport::Response)] }

            it 'skips updating the priority sampler' do
              activate!

              expect(trace_writer.flush_completed).to have_received(:subscribe) do |_name, &block|
                expect(tracer.sampler).to_not receive(:update)
                block.call(responses)
              end
            end
          end
        end
      end
    end

    context 'by default' do
      it_behaves_like 'priority sampling activation' do
        let(:tracer) { Datadog.tracer }
        let(:trace_writer) { Datadog.trace_writer }
      end
    end

    context 'given a tracer' do
      subject(:activate!) { described_class.activate!(tracer: tracer) }

      it_behaves_like 'priority sampling activation' do
        let(:tracer) { Datadog::Tracer.new }
        let(:trace_writer) { Datadog.trace_writer }
      end
    end

    context 'given a trace writer' do
      subject(:activate!) { described_class.activate!(trace_writer: trace_writer) }

      it_behaves_like 'priority sampling activation' do
        let(:tracer) { Datadog.tracer }
        let(:trace_writer) { Datadog::Writer.new }
      end
    end
  end

  describe '::deactivate!' do
    shared_examples_for 'priority sampling deactivation' do
      subject(:deactivate!) { described_class.deactivate!(options) }

      before do
        allow(tracer).to receive(:configure)
        allow(trace_writer.flush_completed).to receive(:unsubscribe)
      end

      context 'when the tracer sampler' do
        before do
          allow(tracer.sampler).to receive(:is_a?)
            .with(Datadog::PrioritySampler)
            .and_return(priority_sampler?)
        end

        context 'is a priority sampler' do
          let(:priority_sampler?) { true }

          context 'and a sampler is provided' do
            let(:options) { super().merge(sampler: sampler) }
            let(:sampler) { Datadog::AllSampler.new }

            it 'configures the tracer with the sampler' do
              deactivate!

              expect(tracer).to have_received(:configure) do |options|
                expect(options).to include(:sampler)
                expect(options[:sampler]).to be(sampler)
              end
            end
          end

          context 'and no sampler is provided' do
            let(:options) { super().reject { |k, _v| k == :sampler } }

            it 'configures the tracer with a new sampler' do
              deactivate!

              expect(tracer).to have_received(:configure) do |options|
                expect(options).to include(:sampler)
                expect(options[:sampler]).to be_a_kind_of(Datadog::Sampling::RuleSampler)
              end
            end
          end
        end

        context 'is not a priority sampler' do
          let(:priority_sampler?) { false }

          it 'does not configure the tracer with a new sampler' do
            deactivate!
            expect(tracer).to_not have_received(:configure)
          end
        end
      end

      context 'unsubscribes from :flush_completed ' do
        it 'as :priority_sampling' do
          deactivate!
          expect(trace_writer.flush_completed).to have_received(:unsubscribe).with(:priority_sampling)
        end
      end
    end

    context 'by default' do
      it_behaves_like 'priority sampling deactivation' do
        let(:options) { {} }

        let(:tracer) { Datadog.tracer }
        let(:trace_writer) { Datadog.trace_writer }
      end
    end

    context 'given a tracer' do
      subject(:deactivate!) { described_class.deactivate!(tracer: tracer) }

      it_behaves_like 'priority sampling deactivation' do
        let(:options) { { tracer: tracer } }

        let(:tracer) { Datadog::Tracer.new }
        let(:trace_writer) { Datadog.trace_writer }
      end
    end

    context 'given a trace writer' do
      subject(:deactivate!) { described_class.deactivate!(trace_writer: trace_writer) }

      it_behaves_like 'priority sampling deactivation' do
        let(:options) { { trace_writer: trace_writer } }

        let(:tracer) { Datadog.tracer }
        let(:trace_writer) { Datadog::Writer.new }
      end
    end
  end
end
