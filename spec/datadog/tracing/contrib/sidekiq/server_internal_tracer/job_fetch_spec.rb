require 'datadog/tracing/contrib/support/spec_helper'
require_relative '../support/helper'

RSpec.describe 'Server internal tracer' do
  include SidekiqServerExpectations

  before do
    unless Datadog::Tracing::Contrib::Sidekiq::Integration.compatible_with_server_internal_tracing?
      skip 'Sidekiq internal server tracing is not supported on this version.'
    end

    skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)

    # Fetches block for 2 seconds when there is nothing in the queue:
    # https://github.com/mperham/sidekiq/blob/v6.2.2/lib/sidekiq/fetch.rb#L7-L9
    # https://redis.io/commands/blpop#blocking-behavior
    #
    # We change the constant here to ensure test runs as fast possible.
    # Timeouts lower then 0.0011 get rounded down to zero.
    require 'sidekiq/fetch' # Require late, as this is not available if `compatible_with_server_internal_tracing?` is false
    stub_const('Sidekiq::BasicFetch::TIMEOUT', { timeout: 0.0011 })
  end

  it 'traces the looping job fetching' do
    expect_in_sidekiq_server(wait_until: -> { fetch_spans.any? { |s| s.name == 'sidekiq.job_fetch' } }) do
      span = spans.find { |s| s.name == 'sidekiq.job_fetch' }

      expect(span.service).to eq(tracer.default_service)
      expect(span.name).to eq('sidekiq.job_fetch')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.job_fetch')
      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('job_fetch')
      expect(span.get_tag('messaging.system')).to eq('sidekiq')
    end
  end
end
