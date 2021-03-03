require 'spec_helper'

require 'ddtrace/transport/traces'
require 'ddtrace/sampling/priority_sampling'

RSpec.describe Datadog::Sampling::PrioritySampling do
  describe '::new_sampler' do
    subject(:new_sampler) { described_class.new_sampler }

    context 'given nothing' do
      it { is_expected.to be_a_kind_of(Datadog::PrioritySampler) }

      it do
        is_expected.to have_attributes(
          pre_sampler: kind_of(Datadog::AllSampler),
          priority_sampler: kind_of(Datadog::Sampling::RuleSampler)
        )
      end
    end

    context 'given a base sampler' do
      subject(:new_sampler) { described_class.new_sampler(base_sampler) }

      context 'that is nil' do
        let(:base_sampler) { nil }

        it { is_expected.to be_a_kind_of(Datadog::PrioritySampler) }

        it do
          is_expected.to have_attributes(
            pre_sampler: kind_of(Datadog::AllSampler),
            priority_sampler: kind_of(Datadog::Sampling::RuleSampler)
          )
        end
      end

      context 'that is a custom sampler' do
        let(:base_sampler) { instance_double(Datadog::Sampler) }

        it { is_expected.to be_a_kind_of(Datadog::PrioritySampler) }

        it do
          is_expected.to have_attributes(
            pre_sampler: base_sampler,
            priority_sampler: kind_of(Datadog::Sampling::RuleSampler)
          )
        end
      end

      context 'that is a PrioritySampler' do
        let(:base_sampler) { Datadog::PrioritySampler.new }
        it { is_expected.to be(base_sampler) }
      end
    end
  end

  describe '::activate!' do
    subject(:activate!) { described_class.activate!(priority_sampler, trace_writer) }

    context 'given a nil arguments' do
      let(:priority_sampler) { nil }
      let(:trace_writer) { nil }

      it { expect { activate! }.to raise_error(ArgumentError) }
    end

    context 'given a priority sampler and trace writer' do
      let(:priority_sampler) { instance_double(Datadog::PrioritySampler) }
      let(:trace_writer) { instance_double(Datadog::Writer, flush_completed: flush_completed) }
      let(:flush_completed) { instance_double(Datadog::Writer::FlushCompleted) }

      it do
        expect(flush_completed).to receive(:subscribe) do |name|
          expect(name).to be(:priority_sampling)
        end

        activate!
      end

      describe 'subscribes with a handler' do
        context 'when given responses' do
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
              expect(flush_completed).to receive(:subscribe) do |_name, &block|
                expect(priority_sampler).to receive(:update).with(service_rates)
                block.call(responses)
              end

              activate!
            end
          end

          context 'that don\'t have #service_rates' do
            let(:responses) { [instance_double(Datadog::Transport::Response)] }

            it 'skips updating the priority sampler' do
              expect(flush_completed).to receive(:subscribe) do |_name, &block|
                expect(priority_sampler).to_not receive(:update)
                block.call(responses)
              end

              activate!
            end
          end
        end
      end
    end
  end

  describe '::deactivate!' do
    subject(:deactivate!) { described_class.deactivate!(trace_writer) }

    context 'given a nil arguments' do
      let(:trace_writer) { nil }
      it { expect { deactivate! }.to raise_error(ArgumentError) }
    end

    context 'given a priority sampler and trace writer' do
      let(:trace_writer) { instance_double(Datadog::Writer, flush_completed: flush_completed) }
      let(:flush_completed) { instance_double(Datadog::Writer::FlushCompleted) }

      it do
        expect(flush_completed).to receive(:unsubscribe).with(:priority_sampling)
        deactivate!
      end
    end
  end
end
