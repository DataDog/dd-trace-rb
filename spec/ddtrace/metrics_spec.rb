require 'spec_helper'

require 'ddtrace'
require 'ddtrace/metrics'
require 'benchmark'

RSpec.describe Datadog::Metrics do
  include_context 'metrics'

  describe 'implementing class' do
    subject(:test_object) { test_class.new }
    let(:test_class) { Class.new { include Datadog::Metrics } }

    it { is_expected.to have_attributes(statsd: nil) }

    describe '#distribution' do
      subject(:distribution) { test_object.send(:distribution, stat, value, options) }
      let(:stat) { :foo }
      let(:value) { 100 }
      let(:options) { nil }

      context 'when #statsd is nil' do
        before(:each) { expect { distribution }.to_not raise_error }
        it { expect(statsd).to_not have_received_distribution_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) { test_object.statsd = statsd }

        context 'and given no options' do
          before(:each) { expect { distribution }.to_not raise_error }
          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'and given options' do
          before(:each) { expect { distribution }.to_not raise_error }

          context 'that are empty' do
            let(:options) { {} }
            it { expect(statsd).to have_received_distribution_metric(stat) }
          end

          context 'that are frozen' do
            let(:options) { {}.freeze }
            it { expect(statsd).to have_received_distribution_metric(stat) }
          end

          context 'that contain :tags' do
            let(:options) { { tags: tags } }
            let(:tags) { %w[foo bar] }
            it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), options) }

            context 'which are frozen' do
              let(:tags) { super().freeze }
              it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), options) }
            end
          end
        end

        context 'which raises an error' do
          before(:each) do
            expect(statsd).to receive(:distribution).and_raise(StandardError)
            expect(Datadog::Tracer.log).to receive(:error)
          end

          it { expect { distribution }.to_not raise_error }
        end
      end
    end

    describe '#increment' do
      subject(:increment) { test_object.send(:increment, stat, options) }
      let(:stat) { :foo }
      let(:options) { nil }

      context 'when #statsd is nil' do
        before(:each) { expect { increment }.to_not raise_error }
        it { expect(statsd).to_not have_received_increment_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) { test_object.statsd = statsd }

        context 'and given no options' do
          before(:each) { expect { increment }.to_not raise_error }
          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'and given options' do
          before(:each) { expect { increment }.to_not raise_error }

          context 'that are empty' do
            let(:options) { {} }
            it { expect(statsd).to have_received_increment_metric(stat) }
          end

          context 'that are frozen' do
            let(:options) { {}.freeze }
            it { expect(statsd).to have_received_increment_metric(stat) }
          end

          context 'that contain :by' do
            let(:options) { { by: count } }
            let(:count) { 1 }
            it { expect(statsd).to have_received_increment_metric(stat, options) }
          end

          context 'that contain :tags' do
            let(:options) { { tags: tags } }
            let(:tags) { %w[foo bar] }
            it { expect(statsd).to have_received_increment_metric(stat, options) }

            context 'which are frozen' do
              let(:tags) { super().freeze }
              it { expect(statsd).to have_received_increment_metric(stat, options) }
            end
          end
        end

        context 'which raises an error' do
          before(:each) do
            expect(statsd).to receive(:increment).and_raise(StandardError)
            expect(Datadog::Tracer.log).to receive(:error)
          end

          it { expect { increment }.to_not raise_error }
        end
      end
    end

    describe '#time' do
      subject(:time) { test_object.send(:time, stat, options, &block) }
      let(:stat) { :foo }
      let(:options) { nil }
      let(:block) { proc {} }

      context 'when #statsd is nil' do
        before(:each) { expect { time }.to_not raise_error }
        it { expect(statsd).to_not have_received_time_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) { test_object.statsd = statsd }

        context 'and given a block' do
          it { expect { |b| test_object.send(:time, stat, &b) }.to yield_control }

          context 'which raises an error' do
            let(:block) { proc { raise error } }
            let(:error) { RuntimeError.new }
            # Expect the given block to raise its errors through
            it { expect { time }.to raise_error(error) }
          end
        end

        context 'and given no options' do
          before(:each) { expect { time }.to_not raise_error }
          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'and given options' do
          before(:each) { expect { time }.to_not raise_error }

          context 'that are empty' do
            let(:options) { {} }
            it { expect(statsd).to have_received_time_metric(stat) }
          end

          context 'that are frozen' do
            let(:options) { {}.freeze }
            it { expect(statsd).to have_received_time_metric(stat) }
          end

          context 'that contain :tags' do
            let(:options) { { tags: tags } }
            let(:tags) { %w[foo bar] }
            it { expect(statsd).to have_received_time_metric(stat, options) }

            context 'which are frozen' do
              let(:tags) { super().freeze }
              it { expect(statsd).to have_received_time_metric(stat, options) }
            end
          end
        end

        context 'which raises an error' do
          before(:each) do
            expect(statsd).to receive(:distribution).and_raise(StandardError)
            expect(Datadog::Tracer.log).to receive(:error)
          end

          it { expect { time }.to_not raise_error }
        end
      end
    end
  end
end
