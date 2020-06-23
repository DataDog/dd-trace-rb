require 'ddtrace/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Disabled tracer' do
  include_context 'Sidekiq testing'

  subject(:perform_async) { job_class.perform_async }
  let(:job_class) { EmptyWorker }

  before do
    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      Datadog.tracer.configure(enabled: false)
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer)
    end
  end

  it 'does not trace' do
    perform_async

    expect(spans).to be_empty
  end
end
