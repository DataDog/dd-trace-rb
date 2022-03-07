# typed: ignore

require 'spec_helper'

require 'datadog/statsd'

require 'datadog/core/encoding'
require 'datadog/tracing'
require 'datadog/tracing/context'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/sampling/rule'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'
require 'ddtrace/transport/http'
require 'ddtrace/transport/http/api'
require 'ddtrace/transport/http/builder'
require 'ddtrace/transport/io'
require 'ddtrace/transport/io/client'
require 'ddtrace/transport/traces'

RSpec.describe 'Tracer integration tests' do
  shared_context 'agent-based test' do
    before do
      skip unless ENV['TEST_DATADOG_INTEGRATION']
    end

    let(:tracer) { Datadog::Tracing.send(:tracer) }
  end

  shared_examples 'flushed trace' do
    it do
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end
  end

  after { tracer.shutdown! }

  describe 'agent receives span' do
    include_context 'agent-based test'

    def create_trace
      tracer.trace('my.op') do |span|
        span.service = 'my.service'
        sleep(0.001)
      end
    end

    def wait_for_flush(stat, num = 1)
      test_repeat.times do
        break if tracer.writer.stats[stat] >= num

        sleep(0.1)
      end
    end

    def agent_receives_span_step1
      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(0)
      expect(stats[:transport].success).to eq(0)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end

    def agent_receives_span_step2
      create_trace

      # Timeout after 3 seconds, waiting for 1 flush
      wait_for_flush(:traces_flushed)

      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:services_flushed]).to be_nil
      # Number of successes will only be 1 since we do not flush services
      expect(stats[:transport].success).to eq(1)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)

      stats[:transport].success
    end

    def agent_receives_span_step3(previous_success)
      create_trace

      # Timeout after 3 seconds, waiting for another flush
      wait_for_flush(:traces_flushed, 2)

      stats = tracer.writer.stats
      expect(stats[:traces_flushed]).to eq(2)
      expect(stats[:services_flushed]).to be_nil
      expect(stats[:transport].success).to be > previous_success
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)
    end

    it do
      agent_receives_span_step1
      success = agent_receives_span_step2
      agent_receives_span_step3(success)
    end

    context 'using unix transport' do
      before do
        skip('ddtrace only supports unix socket connectivity on Linux') unless PlatformHelpers.linux?

        # DEV: To connect to a unix socket in another docker container (the agent container in our case)
        # we need to share a volume with that container. Our current CircleCI setup uses `docker` executors
        # which don't support sharing volumes. We'd have to migrate to using `machine` executors
        # and manage the docker lifecycle ourselves if we want to share unix sockets for testing.
        # In the mean time, this test is being skipped in CI.
        # @see https://support.circleci.com/hc/en-us/articles/360007324514-How-can-I-use-Docker-volume-mounting-on-CircleCI-
        skip("Can't share docker volume to access unix socket in CircleCI currently") if PlatformHelpers.ci?

        Datadog.configure do |c|
          c.tracing.transport_options = proc { |t|
            t.adapter :unix, ENV['TEST_DDAGENT_UNIX_SOCKET']
          }
        end
      end

      it do
        agent_receives_span_step1
        success = agent_receives_span_step2
        agent_receives_span_step3(success)
      end
    end
  end

  describe 'agent receives short span' do
    include_context 'agent-based test'

    before do
      tracer.trace('my.short.op') do |span|
        @span = span
        span.service = 'my.service'
      end

      @first_shutdown = tracer.shutdown!
    end

    let(:stats) { tracer.writer.stats }

    it do
      expect(@first_shutdown).to be true
      expect(@span.finished?).to be true
      expect(stats[:services_flushed]).to be_nil
    end

    it_behaves_like 'flushed trace'
  end

  describe 'rule sampler' do
    include_context 'agent-based test'

    before do
      Datadog.configure do |c|
        c.tracing.sampler = sampler if sampler
      end
    end

    after do
      Datadog.configuration.tracing.sampling.reset!
    end

    shared_examples 'priority sampled' do |sampling_priority|
      it { expect(@sampling_priority).to eq(sampling_priority) }
    end

    shared_examples 'rule sampling rate metric' do |rate|
      it { expect(@rule_sample_rate).to eq(rate) }
    end

    shared_examples 'rate limit metric' do |rate|
      it { expect(@rate_limiter_rate).to eq(rate) }
    end

    let!(:trace) do
      tracer.trace_completed.subscribe do |trace|
        @sampling_priority = trace.sampling_priority
        @rule_sample_rate = trace.rule_sample_rate
        @rate_limiter_rate = trace.rate_limiter_rate
      end

      tracer.trace('my.op').finish

      tracer.shutdown!
    end

    let(:stats) { tracer.writer.stats }
    let(:sampler) { Datadog::Tracing::Sampling::PrioritySampler.new(post_sampler: rule_sampler) }

    context 'with default settings' do
      let(:sampler) { nil }

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
      it_behaves_like 'rule sampling rate metric', nil
      it_behaves_like 'rate limit metric', nil

      context 'with default fallback RateByServiceSampler throttled to 0% sampling rate' do
        let!(:trace) do
          # Force configuration before span is traced
          # DEV: Use MIN because 0.0 is "auto-corrected" to 1.0
          tracer.sampler.update('service:,env:' => Float::MIN)

          super()
        end

        it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT
      end
    end

    context 'with rate set through DD_TRACE_SAMPLE_RATE environment variable' do
      let(:sampler) { nil }

      around do |example|
        ClimateControl.modify('DD_TRACE_SAMPLE_RATE' => '1.0') do
          example.run
        end
      end

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
      it_behaves_like 'rule sampling rate metric', 1.0
      it_behaves_like 'rate limit metric', 1.0
    end

    context 'with low default sample rate' do
      let(:rule_sampler) { Datadog::Tracing::Sampling::RuleSampler.new(default_sample_rate: Float::MIN) }

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
      it_behaves_like 'rule sampling rate metric', Float::MIN
      it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
    end

    context 'with rule' do
      let(:rule_sampler) { Datadog::Tracing::Sampling::RuleSampler.new([rule], **rule_sampler_opt) }
      let(:rule_sampler_opt) { {} }

      context 'matching span' do
        let(:rule) { Datadog::Tracing::Sampling::SimpleRule.new(name: 'my.op') }

        it_behaves_like 'flushed trace'
        it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
        it_behaves_like 'rule sampling rate metric', 1.0
        it_behaves_like 'rate limit metric', 1.0

        context 'with low sample rate' do
          let(:rule) { Datadog::Tracing::Sampling::SimpleRule.new(sample_rate: Float::MIN) }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          it_behaves_like 'rule sampling rate metric', Float::MIN
          it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
        end

        context 'rate limited' do
          let(:rule_sampler_opt) { { rate_limit: Float::MIN } }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 0.0
        end
      end

      context 'not matching span' do
        let(:rule) { Datadog::Tracing::Sampling::SimpleRule.new(name: 'not.my.op') }

        it_behaves_like 'flushed trace'
        # The PrioritySampler was responsible for the sampling decision, not the Rule Sampler.
        it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
        it_behaves_like 'rule sampling rate metric', nil
        it_behaves_like 'rate limit metric', nil
      end
    end
  end

  describe 'shutdown' do
    include_context 'agent-based test'

    context 'executes only once' do
      subject!(:multiple_shutdown) do
        tracer.trace('my.short.op') do |span|
          span.service = 'my.service'
        end

        threads = Array.new(10) do
          Thread.new { tracer.shutdown! }
        end

        threads.each(&:join)
      end

      let(:stats) { tracer.writer.stats }

      it { expect(stats[:services_flushed]).to be_nil }

      it_behaves_like 'flushed trace'
    end

    context 'when sent TERM' do
      before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

      subject(:terminated_process) do
        # Initiate IO pipe
        pipe

        # Fork the process
        fork_id = fork do
          allow(tracer).to receive(:shutdown!).and_wrap_original do |m, *args|
            m.call(*args).tap { write.write(graceful_signal) }
          end

          tracer.trace('my.short.op') do |span|
            span.service = 'my.service'
          end

          sleep(1)
        end

        # Give the fork a chance to setup and sleep
        sleep(0.2)

        # Kill the process
        write.close
        Process.kill('TERM', fork_id) rescue nil

        # Read and return any output
        read.read.tap do
          Process.waitpid(fork_id)
        end
      end

      let(:pipe) { IO.pipe }
      let(:read) { pipe.first }
      let(:write) { pipe.last }
      let(:graceful_signal) { 'graceful' }

      it { expect(terminated_process).to eq(graceful_signal) }
    end
  end

  describe 'sampling priority metrics' do
    # Sampling priority is enabled by default
    context 'when #sampling_priority is set on a child span' do
      before do
        tracer.trace('parent span') do |_parent_span, _parent_trace|
          tracer.trace('child span') do |_child_span, child_trace|
            child_trace.sampling_priority = 10
          end
        end
      end

      it do
        expect(trace.sampling_priority).to eq(10)
      end
    end
  end

  describe 'origin tag' do
    # Sampling priority is enabled by default
    context 'when #sampling_priority is set on a parent span' do
      before do
        tracer.trace('parent span') do |_span, trace|
          trace.origin = 'synthetics'
        end
      end

      it { expect(trace.origin).to eq('synthetics') }
    end
  end

  describe 'sampling priority integration' do
    include_context 'agent-based test'

    it { expect(tracer.sampler).to be_a_kind_of(Datadog::Tracing::Sampling::PrioritySampler) }

    it do
      3.times do |i|
        tracer.trace('parent_span') do
          tracer.trace('child_span') do |_span, trace|
            # I want to keep the trace to which `child_span` belongs
            trace.sampling_priority = i
          end
        end

        try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end
  end

  describe 'Transport::IO' do
    include_context 'agent-based test'

    let(:writer) do
      Datadog::Tracing::Writer.new(
        transport: transport,
        priority_sampler: Datadog::Tracing::Sampling::PrioritySampler.new
      )
    end

    let(:transport) { Datadog::Transport::IO.default(out: out) }
    let(:out) { instance_double(IO) } # Dummy output so we don't pollute STDOUT

    before do
      Datadog.configure do |c|
        c.tracing.writer = writer
      end

      # Verify Transport::IO is configured
      expect(tracer.writer.transport).to be_a_kind_of(Datadog::Transport::IO::Client)
      expect(tracer.writer.transport.encoder).to be(Datadog::Core::Encoding::JSONEncoder)

      # Verify sampling is configured properly
      expect(tracer.sampler).to be_a_kind_of(Datadog::Tracing::Sampling::PrioritySampler)

      # Verify IO is written to
      allow(out).to receive(:puts)

      # Priority sampler does not receive updates because IO is one-way.
      expect(tracer.sampler).to_not receive(:update)
    end

    # Reset the writer
    after do
      Datadog.configure do |c|
        c.tracing.reset!
      end
    end

    it do
      3.times do |i|
        tracer.trace('parent_span') do
          tracer.trace('child_span') do |_span, trace|
            # I want to keep the trace to which `child_span` belongs
            trace.sampling_priority = i
          end
        end

        try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)

        expect(out).to have_received(:puts)
      end
    end
  end

  describe 'Transport::HTTP' do
    include_context 'agent-based test'

    let(:writer) { Datadog::Tracing::Writer.new(transport: transport) }
    let(:transport) { Datadog::Transport::HTTP.default }

    before do
      Datadog.configure do |c|
        c.tracing.priority_sampling = true
        c.tracing.writer = writer
      end

      # Verify Transport::HTTP is configured
      expect(tracer.writer.transport).to be_a_kind_of(Datadog::Transport::Traces::Transport)

      # Verify sampling is configured properly
      expect(tracer.sampler).to be_a_kind_of(Datadog::Tracing::Sampling::PrioritySampler)

      # Verify priority sampler is configured and rates are updated
      expect(tracer.sampler).to receive(:update)
        .with(kind_of(Hash))
        .and_call_original
        .at_least(1).time
    end

    it do
      3.times do |i|
        tracer.trace('parent_span') do
          tracer.trace('child_span') do |_span, trace|
            # I want to keep the trace to which `child_span` belongs
            trace.sampling_priority = i
          end
        end

        try_wait_until(attempts: 20) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end
  end

  describe 'tracer transport' do
    subject(:configure) do
      Datadog.configure do |c|
        c.agent.host = hostname
        c.agent.port = port
        c.tracing.priority_sampling = true
      end
    end

    let(:tracer) { Datadog::Tracing.send(:tracer) }
    let(:hostname) { double('hostname') }
    let(:port) { 34567 }

    context 'when :transport_options' do
      before do
        Datadog.configure do |c|
          c.tracing.transport_options = transport_options
        end
      end

      context 'is provided' do
        let(:transport_options) { proc { |t| on_build.call(t) } }
        let(:on_build) do
          double('on_build').tap do |double|
            expect(double).to receive(:call)
              .with(kind_of(Datadog::Transport::HTTP::Builder))
              .at_least(1).time
            expect(double).to receive(:call)
              .with(kind_of(Datadog::Core::Configuration::AgentSettingsResolver::TransportOptionsResolver))
              .at_least(1).time
          end
        end

        it do
          configure

          tracer.writer.transport.tap do |transport|
            expect(transport).to be_a_kind_of(Datadog::Transport::Traces::Transport)
            expect(transport.current_api.adapter.hostname).to be hostname
            expect(transport.current_api.adapter.port).to be port
          end
        end
      end
    end
  end

  describe 'thread-local context' do
    subject(:tracer) { new_tracer }

    it 'clears context after tracer finishes' do
      before = tracer.send(:call_context)

      expect(before).to be_a(Datadog::Tracing::Context)

      span = tracer.trace('test')
      during = tracer.send(:call_context)

      expect(during).to be(before)
      expect(during.active_trace.id).to_not be nil

      span.finish
      after = tracer.send(:call_context)

      expect(after).to be(during)
      expect(after.active_trace).to be nil
    end

    it 'reuses context for successive traces' do
      span = tracer.trace('test1')
      context1 = tracer.send(:call_context)
      span.finish

      expect(context1).to be_a(Datadog::Tracing::Context)

      span = tracer.trace('test2')
      context2 = tracer.send(:call_context)
      span.finish

      expect(context2).to be(context1)
    end

    context 'with another tracer instance' do
      let(:tracer2) { new_tracer }

      after { tracer2.shutdown! }

      it 'create one thread-local context per tracer' do
        span = tracer.trace('test')
        context = tracer.send(:call_context)

        span2 = tracer2.trace('test2')
        context2 = tracer2.send(:call_context)

        span2.finish
        span.finish

        expect(context).to_not eq(context2)

        expect(tracer.writer.spans[0].name).to eq('test')
        expect(tracer2.writer.spans[0].name).to eq('test2')
      end

      context 'with another thread' do
        it 'create one thread-local context per tracer per thread' do
          span = tracer.trace('test')
          context = tracer.send(:call_context)

          span2 = tracer2.trace('test2')
          context2 = tracer2.send(:call_context)

          Thread.new do
            thread_span = tracer.trace('thread_test')
            @thread_context = tracer.send(:call_context)

            thread_span2 = tracer2.trace('thread_test2')
            @thread_context2 = tracer2.send(:call_context)

            thread_span.finish
            thread_span2.finish
          end.join

          span2.finish
          span.finish

          expect([context, context2, @thread_context, @thread_context2].uniq)
            .to have(4).items

          spans = tracer.writer.spans
          expect(spans[0].name).to eq('test')
          expect(spans[1].name).to eq('thread_test')

          spans2 = tracer2.writer.spans
          expect(spans2[0].name).to eq('test2')
          expect(spans2[1].name).to eq('thread_test2')
        end
      end
    end
  end
end
