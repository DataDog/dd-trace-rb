require 'datadog/tracing/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Tracer configuration' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }

  let(:job_class) { EmptyWorker }
  let(:error_handler) { nil }

  context 'with custom middleware configuration' do
    before do
      Sidekiq::Testing.server_middleware do |chain|
        chain.add(
          Datadog::Tracing::Contrib::Sidekiq::ServerTracer,
          service_name: 'my-service',
          error_handler: error_handler
        )
      end
    end

    it 'instruments with custom values' do
      perform_async

      expect(spans).to have(2).items

      span, _push = spans
      expect(span.service).to eq('my-service')
    end

    context 'with custom error handler' do
      let(:job_class) { ErrorWorker }
      let(:error_handler) { proc { @error_handler_called = true } }

      before do
        stub_const(
          'ErrorWorker',
          Class.new do
            include Sidekiq::Worker

            def perform
              raise ZeroDivisionError, 'job error'
            end
          end
        )
      end

      it 'uses custom error handler' do
        expect { perform_async }.to raise_error
        expect(@error_handler_called).to be_truthy
      end
    end
  end
end
