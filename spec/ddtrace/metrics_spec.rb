require 'spec_helper'

require 'ddtrace'
require 'ddtrace/metrics'
require 'benchmark'

RSpec.describe Datadog::Metrics do
  include_context 'metrics'

  subject(:metrics) { described_class.new(options) }
  let(:options) { { statsd: statsd } }

  it { is_expected.to have_attributes(statsd: statsd) }

  describe '#supported?' do
    # WIP
  end

  describe '#enabled?' do
    subject(:enabled) { metrics.enabled? }

    context 'by default' do
      it { is_expected.to be true }
    end

    context 'when initialized as enabled' do
      let(:options) { super().merge(enabled: true) }
      it { is_expected.to be true }
    end

    context 'when initialized as disabled' do
      let(:options) { super().merge(enabled: false) }
      it { is_expected.to be false }
    end
  end

  describe '#enabled=' do
    subject(:enabled) { metrics.enabled? }
    before { metrics.enabled = status }

    context 'is given true' do
      let(:status) { true }
      it { is_expected.to be true }
    end

    context 'is given false' do
      let(:status) { false }
      it { is_expected.to be false }
    end

    context 'is given nil' do
      let(:status) { nil }
      it { is_expected.to be false }
    end
  end

  describe '#default_statsd_client' do
    # WIP
  end

  describe '#configure' do
    # WIP
  end

  describe '#send_stats?' do
    # WIP
  end

  describe '#distribution' do
    subject(:distribution) { metrics.distribution(stat, value, stat_options) }
    let(:stat) { :foo }
    let(:value) { 100 }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before(:each) do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { distribution }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_distribution_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given no options' do
        before(:each) { expect { distribution }.to_not raise_error }
        it { expect(statsd).to have_received_distribution_metric(stat) }
      end

      context 'and given options' do
        before(:each) { expect { distribution }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }
          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }
          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }
          it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }
            it { expect(statsd).to have_received_distribution_metric(stat, kind_of(Numeric), stat_options) }
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

  describe '#gauge' do
    subject(:gauge) { metrics.gauge(stat, value, stat_options) }
    let(:stat) { :foo }
    let(:value) { 100 }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before(:each) do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { gauge }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_gauge_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given no options' do
        before(:each) { expect { gauge }.to_not raise_error }
        it { expect(statsd).to have_received_gauge_metric(stat) }
      end

      context 'and given options' do
        before(:each) { expect { gauge }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }
          it { expect(statsd).to have_received_gauge_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }
          it { expect(statsd).to have_received_gauge_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }
          it { expect(statsd).to have_received_gauge_metric(stat, kind_of(Numeric), stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }
            it { expect(statsd).to have_received_gauge_metric(stat, kind_of(Numeric), stat_options) }
          end
        end
      end

      context 'which raises an error' do
        before(:each) do
          expect(statsd).to receive(:gauge).and_raise(StandardError)
          expect(Datadog::Tracer.log).to receive(:error)
        end

        it { expect { gauge }.to_not raise_error }
      end
    end
  end

  describe '#increment' do
    subject(:increment) { metrics.increment(stat, stat_options) }
    let(:stat) { :foo }
    let(:stat_options) { nil }

    context 'when #statsd is nil' do
      before(:each) do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { increment }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_increment_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given no options' do
        before(:each) { expect { increment }.to_not raise_error }
        it { expect(statsd).to have_received_increment_metric(stat) }
      end

      context 'and given options' do
        before(:each) { expect { increment }.to_not raise_error }

        context 'that are empty' do
          let(:stat_options) { {} }
          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }
          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'that contain :by' do
          let(:stat_options) { { by: count } }
          let(:count) { 1 }
          it { expect(statsd).to have_received_increment_metric(stat, stat_options) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }
          it { expect(statsd).to have_received_increment_metric(stat, stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }
            it { expect(statsd).to have_received_increment_metric(stat, stat_options) }
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
    subject(:time) { metrics.time(stat, stat_options, &block) }
    let(:stat) { :foo }
    let(:stat_options) { nil }
    let(:block) { proc {} }

    context 'when #statsd is nil' do
      before(:each) do
        allow(metrics).to receive(:statsd).and_return(nil)
        expect { time }.to_not raise_error
      end

      it { expect(statsd).to_not have_received_time_metric(stat) }
    end

    context 'when #statsd is a Datadog::Statsd' do
      context 'and given a block' do
        it { expect { |b| metrics.time(stat, &b) }.to yield_control }

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
          let(:stat_options) { {} }
          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'that are frozen' do
          let(:stat_options) { {}.freeze }
          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'that contain :tags' do
          let(:stat_options) { { tags: tags } }
          let(:tags) { %w[foo bar] }
          it { expect(statsd).to have_received_time_metric(stat, stat_options) }

          context 'which are frozen' do
            let(:tags) { super().freeze }
            it { expect(statsd).to have_received_time_metric(stat, stat_options) }
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
