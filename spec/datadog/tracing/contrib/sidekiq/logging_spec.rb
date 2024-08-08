require 'datadog/tracing/contrib/support/spec_helper'
require_relative 'support/helper'

RSpec.describe 'Sidekiq Logging' do
  include_context 'Sidekiq server'

  before do
    stub_const(
      'EmptyWorker',
      Class.new do
        include Sidekiq::Worker
        def perform
          logger.info('Running EmptyWorker')
        end
      end
    )
  end

  it 'traces the looping job fetching' do
    expect_in_sidekiq_server(log_level: Logger::INFO) do
      EmptyWorker.perform_async

      span = try_wait_until { fetch_spans.find { |s| s.name == 'sidekiq.job' } }

      # Traces in propagation can get truncated to 64-bits by default
      trace_id = Datadog::Tracing::Utils::TraceId.to_low_order(span.trace_id).to_s
      stdout = File.read($stdout)

      expect(stdout).to match(/"trace_id":"#{trace_id}".*start/)

      expect(stdout).to match(/"trace_id":"#{trace_id}".*Running EmptyWorker/)
      expect(stdout).to match(/"span_id":"#{span.id}".*Running EmptyWorker/)

      expect(stdout).to match(/"trace_id":"#{trace_id}".*done/)
    end
  end
end
