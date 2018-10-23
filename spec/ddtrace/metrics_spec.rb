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

    describe '#increment' do
      subject(:increment) { test_object.send(:increment, stat, options) }
      let(:stat) { :foo }
      let(:options) { nil }

      context 'when #statsd is nil' do
        before(:each) { increment }
        it { expect(statsd).to_not increment_stat(stat) }
      end

      context 'when #statsd is a Datadog::Statsd' do
        before(:each) do
          test_object.statsd = statsd
          increment
        end

        context 'and given no options' do
          it { expect(statsd).to increment_stat(stat) }
        end

        context 'and given options' do
          context 'that are empty' do
            let(:options) { {} }
            it { expect(statsd).to increment_stat(stat) }
          end

          context 'that are frozen' do
            let(:options) { {}.freeze }
            it { expect(statsd).to increment_stat(stat) }
          end

          context 'that contain :by' do
            let(:options) { { by: count } }
            let(:count) { 1 }
            it { expect(statsd).to increment_stat(stat).with(options) }
          end

          context 'that contain :tags' do
            let(:options) { { tags: tags } }
            let(:tags) { %w[foo bar] }
            it { expect(statsd).to increment_stat(stat).with(options) }

            context 'which are frozen' do
              let(:tags) { super().freeze }
              it { expect(statsd).to increment_stat(stat).with(options) }
            end
          end
        end
      end
    end
  end
end
