require 'datadog/tracing/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Disabled tracer' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }

  let(:job_class) { EmptyWorker }

  before do
    Datadog.configure do |c|
      c.tracing.enabled = false
    end

    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Tracing::Contrib::Sidekiq::ServerTracer)
    end
  end

  it 'does not trace' do
    perform_async

    expect(spans).to be_empty
  end
end
