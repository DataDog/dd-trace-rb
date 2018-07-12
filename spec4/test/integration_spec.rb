require('helper')
require('ddtrace')
require('ddtrace/tracer')
require('thread')
require('spec_helper')
RSpec.describe 'integration spec' do
  def agent_receives_span_step1(tracer)
    stats = tracer.writer.stats
    expect(stats[:traces_flushed]).to eq(0)
    expect(stats[:transport][:success]).to eq(0)
    expect(stats[:transport][:client_error]).to eq(0)
    expect(stats[:transport][:server_error]).to eq(0)
    expect(stats[:transport][:internal_error]).to eq(0)
  end

  def agent_receives_span_step2(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')
    span = tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish
    test_repeat.times do
      break if tracer.writer.stats[:traces_flushed] >= 1 && tracer.writer.stats[:services_flushed] >= 1
      sleep(0.1)
    end
    stats = tracer.writer.stats

    expect(stats[:traces_flushed]).to eq(1)
    expect(stats[:services_flushed]).to eq(1)
    expect(stats[:transport][:success]).to be >= 1
    expect(stats[:transport][:client_error]).to eq(0)
    expect(stats[:transport][:server_error]).to eq(0)
    expect(stats[:transport][:internal_error]).to eq(0)
    stats[:transport][:success]
  end

  def agent_receives_span_step3(tracer, previous_success)
    span = tracer.start_span('my.op')
    span.service = 'my.service'
    sleep(0.001)
    span.finish
    test_repeat.times do
      break if tracer.writer.stats[:traces_flushed] >= 2
      sleep(0.1)
    end
    stats = tracer.writer.stats
    expect(stats[:traces_flushed]).to eq(2)
    expect(stats[:services_flushed]).to eq(1)
    expect(previous_success).to be < stats[:transport][:success]
    expect(stats[:transport][:client_error]).to eq(0)
    expect(stats[:transport][:server_error]).to eq(0)
    expect(stats[:transport][:internal_error]).to eq(0)
  end

  def agent_receives_short_span(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')
    span = tracer.start_span('my.short.op')
    span.service = 'my.service'
    span.finish
    first_shutdown = tracer.shutdown!
    stats = tracer.writer.stats
    expect(first_shutdown).to be_truthy
    expect(span.finished?).to be_truthy
    expect(stats[:traces_flushed]).to eq(1)
    expect(stats[:services_flushed]).to eq(1)
    expect(stats[:transport][:client_error]).to eq(0)
    expect(stats[:transport][:server_error]).to eq(0)
    expect(stats[:transport][:internal_error]).to eq(0)
  end

  def shutdown_exec_only_once(tracer)
    tracer.set_service_info('my.service', 'rails', 'web')
    span = tracer.start_span('my.short.op')
    span.service = 'my.service'
    span.finish
    mutex = Mutex.new
    shutdown_results = []
    threads = Array.new(10) do
      Thread.new { mutex.synchronize { (shutdown_results << tracer.shutdown!) } }
    end
    threads.each(&:join)
    stats = tracer.writer.stats
    expect(shutdown_results.count(true)).to eq(1)
    expect(stats[:traces_flushed]).to eq(1)
    expect(stats[:services_flushed]).to eq(1)
    expect(stats[:transport][:client_error]).to eq(0)
    expect(stats[:transport][:server_error]).to eq(0)
    expect(stats[:transport][:internal_error]).to eq(0)
  end
  it('agent receives span') do
    skip unless ENV['TEST_DATADOG_INTEGRATION']
    tracer = Datadog::Tracer.new
    tracer.configure(enabled:
                         true, hostname:
        ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
                     port: ENV.fetch('TEST_DDAGENT_PORT', 8126))
    agent_receives_span_step1(tracer)
    success = agent_receives_span_step2(tracer)
    agent_receives_span_step3(tracer, success)
  end
  it('short span') do
    skip unless ENV['TEST_DATADOG_INTEGRATION'] || (RUBY_PLATFORM != 'java')
    tracer = Datadog::Tracer.new
    tracer.configure(enabled: true, hostname:
        ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
                     port: ENV.fetch('TEST_DDAGENT_PORT', 8126))
    agent_receives_short_span(tracer)
  end
  it('shutdown exec once') do
    skip unless ENV['TEST_DATADOG_INTEGRATION'] || (RUBY_PLATFORM != 'java')
    tracer = Datadog::Tracer.new
    tracer.configure(enabled: true,
                     hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
                     port: ENV.fetch('TEST_DDAGENT_PORT', 8126))
    shutdown_exec_only_once(tracer)
  end
  it('sampling priority metric propagation') do
    tracer = get_test_tracer
    tracer.configure(priority_sampling: true)
    tracer.writer = FauxWriter.new(priority_sampler: Datadog::PrioritySampler.new)
    span_a = tracer.start_span('span_a')
    span_b = tracer.start_span('span_b', child_of: span_a.context)
    span_b.context.sampling_priority = 10
    span_b.finish
    span_a.finish
    try_wait_until { tracer.writer.spans(:keep).any? }
    expect(span_a.get_metric(Datadog::Ext::DistributedTracing::SAMPLING_PRIORITY_KEY)).to(eq(10))
  end
  it('priority sampling integration') do
    3.times do |i|
      tracer = Datadog::Tracer.new
      tracer.configure(enabled: true,
                       hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
                       port: ENV.fetch('TEST_DDAGENT_PORT', 8126),
                       priority_sampling: true)
      span_a = tracer.start_span('span_a')
      span_b = tracer.start_span('span_b', child_of: span_a.context)
      span_b.context.sampling_priority = i
      span_b.finish
      span_a.finish
      try_wait_until(attempts: 20) do
        (tracer.writer.stats[:traces_flushed] >= 1)
      end
      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to(eq(1))
      expect(stats[:transport][:client_error]).to(eq(0))
      expect(stats[:transport][:server_error]).to(eq(0))
      expect(stats[:transport][:internal_error]).to(eq(0))
    end
  end
end
