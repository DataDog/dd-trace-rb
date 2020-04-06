require 'spec_helper'

require 'datadog/statsd'
require 'ddtrace/patcher'
require 'ddtrace/configuration'

RSpec.describe Datadog::Configuration do
  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::Configuration }) }

    describe '#configure' do
      subject(:configure) { test_class.configure }

      context 'when replacing a tracer' do
        let(:old_tracer) { Datadog::Tracer.new }
        let(:new_tracer) { Datadog::Tracer.new }

        before do
          expect(old_tracer).to receive(:shutdown!)

          test_class.configure { |c| c.tracer = old_tracer }
          test_class.configure { |c| c.tracer = new_tracer }
        end

        it 'replaces the old tracer and shuts it down' do
          expect(test_class.tracer).to be new_tracer
        end
      end

      context 'when reusing the same tracer' do
        let(:tracer) { Datadog::Tracer.new }

        before do
          expect(tracer).to_not receive(:shutdown!)

          test_class.configure { |c| c.tracer = tracer }
          test_class.configure { |c| c.tracer = tracer }
        end

        it 'replaces the old tracer and shuts it down' do
          expect(test_class.tracer).to be tracer
        end
      end

      context 'when not changing the tracer' do
        let(:tracer) { Datadog::Tracer.new }

        before do
          expect(tracer).to_not receive(:shutdown!)

          test_class.configure { |c| c.tracer = tracer }
          test_class.configure { |_c| }
        end

        it 'replaces the old tracer and shuts it down' do
          expect(test_class.tracer).to be tracer
        end
      end

      context 'when replacing metrics' do
        let(:old_statsd) { instance_double(Datadog::Statsd) }
        let(:new_statsd) { instance_double(Datadog::Statsd) }

        before do
          expect(old_statsd).to receive(:close)

          test_class.configure { |c| c.runtime_metrics.statsd = old_statsd }
          test_class.configure { |c| c.runtime_metrics.statsd = new_statsd }
        end

        it 'replaces the old Statsd and closes it' do
          expect(test_class.runtime_metrics.statsd).to be new_statsd
        end
      end

      context 'when reusing metrics' do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          expect(statsd).to_not receive(:close)

          test_class.configure { |c| c.runtime_metrics.statsd = statsd }
          test_class.configure { |c| c.runtime_metrics.statsd = statsd }
        end

        it 'replaces the old Statsd and closes it' do
          expect(test_class.runtime_metrics.statsd).to be statsd
        end
      end

      context 'when not changing the metrics' do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          expect(statsd).to_not receive(:close)

          test_class.configure { |c| c.runtime_metrics.statsd = statsd }
          test_class.configure { |_c| }
        end

        it 'replaces the old Statsd and closes it' do
          expect(test_class.runtime_metrics.statsd).to be statsd
        end
      end
    end
  end
end
