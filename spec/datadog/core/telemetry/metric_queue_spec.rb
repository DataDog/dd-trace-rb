require 'spec_helper'

require 'datadog/core/telemetry/metric_queue'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::MetricQueue do
  let(:metric_queue) { described_class.new }
  let(:metric_klass) { Datadog::Core::Telemetry::Metric::Count }
  subject(:empty_metrics_queue) do
    {
      'generate-metrics' => {},
      'distributions' => {},
    }
  end

  describe '#add_metric' do
    context 'no previous metric' do
      it 'creates a new metric entry point and stores it' do
        expect(metric_queue.metrics).to eq(empty_metrics_queue)
        expect(metric_klass).to receive(:new).with('test_metric_name', { foo: :bar }).and_call_original
        expect_any_instance_of(metric_klass).to receive(:update_value).with(1).and_call_original
        metric_queue.add_metric(
          'test_namespace',
          'test_metric_name',
          1,
          { foo: :bar },
          metric_klass
        )

        expect(metric_queue.metrics[metric_klass.request_type]['test_namespace']).to_not be_nil
        expect(metric_queue.metrics[metric_klass.request_type]['test_namespace']['test_metric_name']).to_not be_nil

        metric_instace = metric_queue.metrics[metric_klass.request_type]['test_namespace']['test_metric_name']
        expect(metric_instace).to be_a(metric_klass)
      end
    end

    context 'previous metric' do
      it 'just updates values and stores metric back' do
        metric_queue.add_metric(
          'test_namespace',
          'test_metric_name',
          1,
          { foo: :bar },
          metric_klass
        )

        expect(metric_klass).to_not receive(:new)
        expect_any_instance_of(metric_klass).to receive(:update_value).with(2).and_call_original

        metric_queue.add_metric(
          'test_namespace',
          'test_metric_name',
          2,
          { foo: :bar },
          metric_klass
        )

        metric_instace = metric_queue.metrics[metric_klass.request_type]['test_namespace']['test_metric_name']
        expect(metric_instace).to be_a(metric_klass)
      end
    end
  end

  describe '#build_metrics_payload' do
    it 'yields metric_type and assiciated payload' do
      expect(Time).to receive(:now).and_return(1234)

      metric_queue.add_metric(
        'test_namespace',
        'test_metric_name',
        1,
        { foo: :bar },
        metric_klass
      )

      metric_queue.add_metric(
        'test_namespace_two',
        'test_metric_name_distribution',
        1,
        { foo: :bar },
        Datadog::Core::Telemetry::Metric::Distribution
      )

      expect do |b|
        metric_queue.build_metrics_payload(&b)
      end.to yield_successive_args(
        [
          'generate-metrics', {
            :namespace => 'test_namespace',
            :series =>
            [
              {
                :metric => 'test_metric_name',
                :tags => ['foo:bar'],
                :values => [[1234, 1]],
                :type => 'count',
                :common => true
              }
            ]
          }
        ],
        [
          'distributions', {
            :namespace => 'test_namespace_two',
            :series => [
              {
                :metric => 'test_metric_name_distribution',
                :tags => ['foo:bar'],
                :values => [1],
                :type => 'distributions',
                :common => true
              }
            ]
          }
        ]
      )
    end

    context 'empty metrics' do
      it 'does not yield information' do
        expect do |b|
          metric_queue.build_metrics_payload(&b)
        end.not_to yield_control
      end
    end
  end
end
