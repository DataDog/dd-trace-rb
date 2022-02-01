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

  it 'traces the looping heartbeat' do
    expect_in_sidekiq_server do
      span = spans.find { |s| s.service == tracer.default_service && s.name == 'sidekiq.heartbeat' }

      expect(span.service).to eq(tracer.default_service)
      expect(span.name).to eq('sidekiq.heartbeat')
      expect(span.span_type).to eq('worker')
      expect(span.resource).to eq('sidekiq.heartbeat')
      expect(span).to_not have_error
      expect(span.get_tag(Datadog::Ext::Metadata::TAG_COMPONENT)).to eq('sidekiq')
      expect(span.get_tag(Datadog::Ext::Metadata::TAG_OPERATION)).to eq('heartbeat')
    end
  end
end
