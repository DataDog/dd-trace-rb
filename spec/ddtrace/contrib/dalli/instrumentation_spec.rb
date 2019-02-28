require 'spec_helper'

require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/patcher'

RSpec.describe 'Dalli instrumentation' do
  let(:test_host) { ENV.fetch('TEST_MEMCACHED_HOST', '127.0.0.1') }
  let(:test_port) { ENV.fetch('TEST_MEMCACHED_PORT', '11211') }

  let(:client) { ::Dalli::Client.new("#{test_host}:#{test_port}") }
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  def all_spans
    tracer.writer.spans(:keep)
  end

  # Enable the test tracer
  before(:each) do
    Datadog.configure do |c|
      c.use :dalli, configuration_options
    end
  end

  after(:each) { Datadog.registry[:dalli].reset_configuration! }

  it 'calls instrumentation' do
    client.set('abc', 123)
    try_wait_until { all_spans.any? }

    span = all_spans.first
    expect(all_spans.size).to eq(1)
    expect(span.service).to eq('memcached')
    expect(span.name).to eq('memcached.command')
    expect(span.resource).to eq('SET')
    expect(span.get_tag('memcached.command')).to eq('set abc 123 0 0')
    expect(span.get_tag('out.host')).to eq(test_host)
    expect(span.get_tag('out.port')).to eq(test_port)
  end
end
