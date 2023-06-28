require 'datadog/tracing/contrib/support/spec_helper'
require_relative '../support/helper'

RSpec.describe 'Server internal tracer heartbeat' do
  include SidekiqServerExpectations

  before do
    unless Datadog::Tracing::Contrib::Sidekiq::Integration.compatible_with_server_internal_tracing?
      skip 'Sidekiq internal server tracing is not supported on this version.'
    end

    skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)
  end

  it 'traces the looping heartbeat' do
    expect_in_sidekiq_server(wait_until: -> { fetch_spans.any? { |s| s.name == 'sidekiq.heartbeat' } }) do
      span = spans.find { |s| s.service == tracer.default_service && s.name == 'sidekiq.heartbeat' }

      expect(span.service).to eq(tracer.default_service)
      expect(span.name).to eq('sidekiq.heartbeat')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.heartbeat')
      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('heartbeat')
      expect(span.get_tag('messaging.system')).to eq('sidekiq')
    end
  end

  context 'traces the stop command' do
    it do
      expect_after_stopping_sidekiq_server do
        span = spans.find { |s| s.name == 'sidekiq.stop' }

        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('sidekiq.stop')
        expect(span.span_type).to eq('worker')
        expect(span.resource).to eq('sidekiq.stop')
        expect(span).to_not have_error
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('sidekiq')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('stop')
        expect(span.get_tag('messaging.system')).to eq('sidekiq')
      end
    end
  end
end
