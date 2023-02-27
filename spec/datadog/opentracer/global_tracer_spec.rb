require 'spec_helper'

require 'datadog/tracing'
require 'datadog/tracing/tracer'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::GlobalTracer do
  context 'when included into OpenTracing' do
    describe '#global_tracer=' do
      subject(:global_tracer) { OpenTracing.global_tracer = tracer }

      after { Datadog.configuration.tracing.instance = Datadog::Tracing::Tracer.new }

      context 'when given a Datadog::OpenTracer::Tracer' do
        let(:tracer) { Datadog::OpenTracer::Tracer.new }

        it do
          expect(global_tracer).to be(tracer)
          expect(Datadog::Tracing.send(:tracer)).to be(tracer.datadog_tracer)
        end
      end

      context 'when given some unknown kind of tracer' do
        let(:tracer) { double('other tracer') }

        it do
          expect(global_tracer).to be(tracer)
          expect(Datadog::Tracing.send(:tracer)).to_not be(tracer)
        end
      end
    end
  end
end
