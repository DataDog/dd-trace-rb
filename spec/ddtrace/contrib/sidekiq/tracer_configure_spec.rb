require 'ddtrace/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Tracer configuration' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }
  let(:job_class) { EmptyWorker }

  context 'with custom middleware configuration' do
    before do
      Sidekiq::Testing.server_middleware do |chain|
        chain.add(
          Datadog::Contrib::Sidekiq::ServerTracer,
          service_name: 'my-service'
        )
      end
    end

    it 'instruments with custom values' do
      perform_async

      expect(spans).to have(2).items

      span, _push = spans
      expect(span.service).to eq('my-service')
    end
  end
end
