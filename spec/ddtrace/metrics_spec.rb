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
        before(:each) { distribution }
        it { expect(statsd).to_not have_received_distribution_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) do
          test_object.statsd = statsd
          distribution
        end

        context 'and given no options' do
          it { expect(statsd).to have_received_distribution_metric(stat) }
        end

        context 'and given options' do
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
      end
    end

    describe '#increment' do
      subject(:increment) { test_object.send(:increment, stat, options) }
      let(:stat) { :foo }
      let(:options) { nil }

      context 'when #statsd is nil' do
        before(:each) { increment }
        it { expect(statsd).to_not have_received_increment_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) do
          test_object.statsd = statsd
          increment
        end

        context 'and given no options' do
          it { expect(statsd).to have_received_increment_metric(stat) }
        end

        context 'and given options' do
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
      end
    end

    describe '#time' do
      subject(:time) { test_object.send(:time, stat, options, &block) }
      let(:stat) { :foo }
      let(:options) { nil }
      let(:block) { proc {} }

      context 'when #statsd is nil' do
        before(:each) { time }
        it { expect(statsd).to_not have_received_time_metric(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) do
          test_object.statsd = statsd
          time
        end

        context 'and given a block' do
          it { expect { |b| test_object.send(:time, stat, &b) }.to yield_control }
        end

        context 'and given no options' do
          it { expect(statsd).to have_received_time_metric(stat) }
        end

        context 'and given options' do
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
      end
    end
  end
end
