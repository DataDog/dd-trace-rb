# typed: ignore
require 'ddtrace/contrib/support/spec_helper'
require_relative '../support/helper'

RSpec.describe 'Server internal tracer' do
  include SidekiqServerExpectations

  before do
    unless Datadog::Contrib::Sidekiq::Integration.compatible_with_server_internal_tracing?
      skip 'Sidekiq internal server tracing is not support on this version.'
    end

    skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)
  end

  around do |example|
    original_poll_interval_average = Sidekiq.options[:poll_interval_average]
    Sidekiq.options[:poll_interval_average] = 0

    example.run

    Sidekiq.options[:poll_interval_average] = original_poll_interval_average
  end

  it 'traces the looping scheduled push' do
    expect_in_sidekiq_server(duration: 6) do
      span = spans.find { |s| s.service == 'sidekiq' && s.name == 'sidekiq.scheduled_push' }

      expect(span.service).to eq('sidekiq')
      expect(span.name).to eq('sidekiq.scheduled_push')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.scheduled_push')
      expect(span).to_not have_error
    end
  end
end
