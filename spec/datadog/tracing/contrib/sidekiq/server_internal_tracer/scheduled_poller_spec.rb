require 'datadog/tracing/contrib/support/spec_helper'
require_relative '../support/helper'

RSpec.describe 'Server internal tracer' do
  include SidekiqServerExpectations

  before do
    unless Datadog::Tracing::Contrib::Sidekiq::Integration.compatible_with_server_internal_tracing?
      skip 'Sidekiq internal server tracing is not supported on this version.'
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
    expect_in_sidekiq_server(wait_until: -> { fetch_spans.any? { |s| s.name == 'sidekiq.scheduled_push' } }) do
      span = spans.find { |s| s.name == 'sidekiq.scheduled_push' }

      expect(span.service).to eq(tracer.default_service)
      expect(span.name).to eq('sidekiq.scheduled_push')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.scheduled_push')
      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('scheduled_push')
      expect(span.get_tag('messaging.system')).to eq('sidekiq')
    end
  end

  it 'traces the looping scheduled wait' do
    expect_in_sidekiq_server(wait_until: -> { fetch_spans.any? { |s| s.name == 'sidekiq.scheduled_poller_wait' } }) do
      span = spans.find { |s| s.name == 'sidekiq.scheduled_poller_wait' }

      expect(span.service).to eq(tracer.default_service)
      expect(span.name).to eq('sidekiq.scheduled_poller_wait')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.scheduled_poller_wait')
      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('scheduled_poller_wait')
      expect(span.get_tag('messaging.system')).to eq('sidekiq')
    end
  end
end
