require 'spec_helper'

require 'ddtrace/opentracer'
require 'datadog/statsd'

RSpec.describe 'ddtrace integration' do
  context 'after shutdown' do
    subject(:shutdown!) { Datadog.shutdown! }

    before do
      Datadog.configure do |c|
        c.diagnostics.health_metrics.enabled = true
      end

      shutdown!
    end

    after do
      Datadog.configuration.diagnostics.health_metrics.reset!
    end

    context 'calling public apis' do
      it 'does not error on tracing' do
        span = Datadog.tracer.trace('test')

        expect(span.finish).to be_truthy
      end

      it 'does not error on tracing with block' do
        value = Datadog.tracer.trace('test') do |span|
          expect(span).to be_a(Datadog::Span)
          :return
        end

        expect(value).to be(:return)
      end

      it 'does not error on logging' do
        expect(Datadog.logger.info('test')).to be_truthy
      end

      it 'does not error on configuration access' do
        expect(Datadog.configuration.diagnostics.debug).to be(false)
      end

      it 'does not error on reporting health metrics' do
        expect(Datadog.health_metrics.queue_accepted(1)).to be_a(Integer)
      end

      context 'with OpenTracer' do
        before do
          skip 'OpenTracing not supported' unless Datadog::OpenTracer.supported?

          OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
        end

        let(:tracer) do
          OpenTracing.global_tracer
        end

        it 'does not error on tracing' do
          span = tracer.start_span('test')

          expect { span.finish }.to_not raise_error
        end

        it 'does not error on tracing with block' do
          scope = tracer.start_span('test') do |scp|
            expect(scp).to be_a(OpenTracing::Scope)
          end

          expect(scope).to be_a(OpenTracing::Span)
        end

        it 'does not error on registered scope tracing' do
          span = tracer.start_active_span('test')

          expect { span.close }.to_not raise_error
        end

        it 'does not error on registered scope tracing with block' do
          scope = tracer.start_active_span('test') do |scp|
            expect(scp).to be_a(OpenTracing::Scope)
          end

          expect(scope).to be_a(OpenTracing::Scope)
        end
      end
    end
  end
end
