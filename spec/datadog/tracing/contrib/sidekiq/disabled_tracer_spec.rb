require "datadog/tracing/contrib/support/spec_helper"
require_relative "support/helper"

RSpec.describe "Disabled tracer" do
  include_context "Sidekiq testing"

  subject(:perform_async) { job_class.perform_async }

  let(:job_class) { EmptyWorker }

  before do
    Datadog.configure do |c|
      c.tracing.enabled = false
    end

    Sidekiq.configure_client do |config|
      config.client_middleware.clear
      config.client_middleware do |chain|
        chain.add(Datadog::Tracing::Contrib::Sidekiq::ClientTracer)
      end
    end

    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Tracing::Contrib::Sidekiq::ServerTracer)
    end
  end

  it "does not trace" do
    perform_async

    expect(spans).to be_empty
  end

  it "pushes and runs the job without starting a trace" do
    expect(Datadog::Tracing).to_not receive(:trace)

    expect(perform_async).to be_a(String)
  end
end
