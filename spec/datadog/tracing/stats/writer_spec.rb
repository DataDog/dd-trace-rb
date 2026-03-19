# frozen_string_literal: true

require 'datadog/core'
require 'datadog/core/ddsketch'
require 'datadog/tracing/span'
require 'datadog/tracing/stats/writer'
require 'datadog/tracing/stats/ext'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Stats::Writer do
  before do
    skip_if_libdatadog_not_supported
  end

  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, warn: nil) }
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettings.new(adapter: :test, hostname: 'localhost', port: 9999)
  end

  let(:writer) do
    described_class.new(
      agent_settings: agent_settings,
      logger: logger,
      env: 'test',
      service: 'test-service',
      version: '1.0.0',
      runtime_id: 'test-runtime-id',
      container_id: 'test-container-id',
      interval: 60.0, # Long interval so the periodic flush doesn't interfere with tests
    )
  end

  after do
    writer.stop(true)
    writer.join(1)
  end

  def build_eligible_span(now: Time.now)
    span = Datadog::Tracing::Span.new(
      'test.span',
      service: 'test-service',
      resource: 'GET /test',
      type: 'web',
      parent_id: 0,
      start_time: now - 1,
      duration: 0.5,
    )
    span.instance_variable_set(:@end_time, now - 0.5)
    span.set_metric(Datadog::Tracing::Metadata::Ext::TAG_TOP_LEVEL, 1.0)
    span
  end

  describe '#add_span' do
    it 'adds a span to the concentrator' do
      span = build_eligible_span
      writer.add_span(span)

      expect(writer.concentrator.buckets).not_to be_empty
    end

    it 'ignores non-eligible spans' do
      span = Datadog::Tracing::Span.new(
        'internal.span',
        service: 'test-service',
        resource: 'internal',
      )
      writer.add_span(span)

      expect(writer.concentrator.buckets).to be_empty
    end
  end

  describe '#agent_peer_tags=' do
    it 'updates the concentrator peer tags' do
      expect(writer.concentrator).to receive(:agent_peer_tags=).with(['custom.tag'])
      writer.agent_peer_tags = ['custom.tag']
    end
  end

  describe '#stop' do
    it 'can be stopped gracefully' do
      expect { writer.stop(true) }.not_to raise_error
    end
  end
end
