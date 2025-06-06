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
require 'datadog/tracing/transport/http'
require 'datadog/tracing/transport/http/api'
require 'datadog/tracing/transport/io'
require 'datadog/tracing/transport/io/client'
require 'datadog/tracing/transport/traces'

RSpec.describe 'Tracer integration tests' do
  shared_context 'agent-based test' do
    skip_unless_integration_testing_enabled

    before do
      # Ensure background Writer worker doesn't wait, making tests faster.
      stub_const('Datadog::Tracing::Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL', 0)

      # Capture trace segments as they are about to be serialized
      segments = trace_segments
      allow_any_instance_of(Datadog::Tracing::Transport::TraceFormatter)
        .to receive(:format!).and_wrap_original do |original|
          segments << original.call
        end
    end

    def tracer
      # Do not cache tracer object in a `let`, as trace is recreated on `Datadog.configure`
      Datadog::Tracing.send(:tracer)
    end

    let(:trace_segments) { [] }
    let(:span) do
      expect(trace_segments).to have(1).item
      expect(trace_segments[0].spans).to have(1).item

      trace_segments[0].spans[0]
    end
    let(:sampling_priority) { span.get_tag('_sampling_priority_v1') }
  end

  shared_examples 'flushed trace' do
    it do
      expect(stats).to include(traces_flushed: 1)
      expect(stats[:transport])
        .to have_attributes(
          client_error: 0,
          server_error: 0,
          internal_error: 0
        )
    end
  end

  shared_examples 'flushed no trace' do
    it { expect(stats).to include(traces_flushed: 0) }
  end

  shared_examples 'priority sampled' do |expected|
    it { expect(sampling_priority).to eq(expected) }
  end

  shared_examples 'sampling decision' do |sampling_decision|
    it { expect(span.get_tag('_dd.p.dm')).to eq(sampling_decision) }
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
        skip('datadog only supports unix socket connectivity on Linux') unless PlatformHelpers.linux?

        # DEV: To connect to a unix socket in another docker container (the agent container in our case)
        # we need to share a volume with that container. Our current CircleCI setup uses `docker` executors
        # which don't support sharing volumes. We'd have to migrate to using `machine` executors
        # and manage the docker lifecycle ourselves if we want to share unix sockets for testing.
        # In the mean time, this test is being skipped in CI.
        # @see https://support.circleci.com/hc/en-us/articles/360007324514-How-can-I-use-Docker-volume-mounting-on-CircleCI-
        skip("Can't share docker volume to access unix socket in CircleCI currently") if PlatformHelpers.ci?

        Datadog.configure do |c|
          c.agent.uds_path = ENV['TEST_DDAGENT_UNIX_SOCKET']
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

    shared_examples 'rule sampling rate metric' do |rate|
      it { expect(@rule_sample_rate).to eq(rate) }
    end

    shared_examples 'rate limit metric' do |rate|
      it { expect(@rate_limiter_rate).to eq(rate) }
    end

    shared_examples 'sampling decision' do |sampling_decision|
      it { expect(span.get_tag('_dd.p.dm')).to eq(sampling_decision) }
    end

    let!(:trace) do
      tracer.trace_completed.subscribe do |trace|
        @sampling_priority = trace.sampling_priority
        @rule_sample_rate = trace.rule_sample_rate
        @rate_limiter_rate = trace.rate_limiter_rate
        @span = trace.spans[0]
      end

      tracer.trace('my.op', service: 'my.service') do |span|
        span.set_tag('tag', 'tag_value')
        span.set_tag('tag2', 'tag_value2')
        span.resource = 'my.resource'
      end

      try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }

      tracer.shutdown!
    end

    let(:stats) { tracer.writer.stats }
    let(:sampler) { Datadog::Tracing::Sampling::PrioritySampler.new(post_sampler: rule_sampler) }
    let(:sampling_priority) { @sampling_priority }
    let(:local_root_span) { trace_segments[0].spans.find { |x| x.parent_id == 0 } }
    let(:span) { local_root_span }

    context 'with default settings' do
      let(:sampler) { nil }

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
      it_behaves_like 'rule sampling rate metric', nil
      it_behaves_like 'rate limit metric', nil
      it_behaves_like 'sampling decision', '-0'

      context 'with default fallback RateByServiceSampler throttled to 0% sampling rate' do
        let!(:trace) do
          # Force configuration before span is traced
          # DEV: Use MIN because 0.0 is "auto-corrected" to 1.0
          tracer.sampler.update({ 'service:,env:' => Float::MIN })

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
      it_behaves_like 'sampling decision', '-3'
    end

    context 'with low default sample rate' do
      let(:rule_sampler) { Datadog::Tracing::Sampling::RuleSampler.new(default_sample_rate: Float::MIN) }

      it_behaves_like 'flushed trace'
      it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
      it_behaves_like 'rule sampling rate metric', Float::MIN
      it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
      it_behaves_like 'sampling decision', nil
    end

    shared_context 'DD_TRACE_SAMPLING_RULES configuration' do
      let(:sampler) { nil }
      let(:rules_json) { [rule].to_json }

      around do |example|
        ClimateControl.modify('DD_TRACE_SAMPLING_RULES' => rules_json) do
          example.run
        end
      end
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
        it_behaves_like 'sampling decision', '-3'

        context 'set through DD_TRACE_SAMPLING_RULES environment variable' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) { { name: 'my.op', sample_rate: 1.0 } }
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 1.0
          it_behaves_like 'sampling decision', '-3'
        end

        context 'with a matching resource name' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) { { resource: 'my.resource', sample_rate: 1.0 } }
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 1.0
          it_behaves_like 'sampling decision', '-3'
        end

        context 'with a matching service name' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) { { service: 'my.service', sample_rate: 1.0 } }
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 1.0
          it_behaves_like 'sampling decision', '-3'
        end

        context 'with matching tags' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) { { tags: { tag: 'tag_value', tag2: 'tag_value2' }, sample_rate: 1.0 } }
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 1.0
          it_behaves_like 'sampling decision', '-3'
        end

        context 'with matching tags and matching service and matching resource' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) do
              { resource: 'my.resource', service: 'my.service', tags: { tag: 'tag_value', tag2: 'tag_value2' },
                sample_rate: 1.0 }
            end
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 1.0
          it_behaves_like 'sampling decision', '-3'
        end

        context 'with not matching tags and matching service and matching resource' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) do
              { resource: 'my.resource', service: 'my.service', tags: { tag: 'wrong_tag_value' },
                sample_rate: 1.0 }
            end
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
          it_behaves_like 'rule sampling rate metric', nil # Rule is not applied
          it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
          it_behaves_like 'sampling decision', '-0'
        end

        context 'drop with matching tags and matching service and matching resource' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) do
              { resource: 'my.resource', service: 'my.service', tags: { tag: 'tag_value' },
                sample_rate: 0 }
            end
          end

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          it_behaves_like 'rule sampling rate metric', 0.0
          it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
          it_behaves_like 'sampling decision', nil
        end

        context 'with low sample rate' do
          let(:rule) { Datadog::Tracing::Sampling::SimpleRule.new(sample_rate: Float::MIN) }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          it_behaves_like 'rule sampling rate metric', Float::MIN
          it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
          it_behaves_like 'sampling decision', nil

          context 'set through DD_TRACE_SAMPLING_RULES environment variable' do
            include_context 'DD_TRACE_SAMPLING_RULES configuration' do
              let(:rule) { { sample_rate: Float::MIN } }
            end

            it_behaves_like 'flushed trace'
            it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
            it_behaves_like 'rule sampling rate metric', Float::MIN
            it_behaves_like 'rate limit metric', nil # Rate limiter is never reached, thus has no value to provide
            it_behaves_like 'sampling decision', nil
          end
        end

        context 'rate limited' do
          let(:rule_sampler_opt) { { rate_limit: Float::MIN } }

          it_behaves_like 'flushed trace'
          it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          it_behaves_like 'rule sampling rate metric', 1.0
          it_behaves_like 'rate limit metric', 0.0
          it_behaves_like 'sampling decision', nil
        end
      end

      context 'not matching span' do
        let(:rule) { Datadog::Tracing::Sampling::SimpleRule.new(name: 'not.my.op') }

        it_behaves_like 'flushed trace'
        # The PrioritySampler was responsible for the sampling decision, not the Rule Sampler.
        it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
        it_behaves_like 'rule sampling rate metric', nil
        it_behaves_like 'rate limit metric', nil
        it_behaves_like 'sampling decision', '-0'

        context 'set through DD_TRACE_SAMPLING_RULES environment variable' do
          include_context 'DD_TRACE_SAMPLING_RULES configuration' do
            let(:rule) { { name: 'not.my.op' } }

            it_behaves_like 'flushed trace'
            # The PrioritySampler was responsible for the sampling decision, not the Rule Sampler.
            it_behaves_like 'priority sampled', Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP
            it_behaves_like 'rule sampling rate metric', nil
            it_behaves_like 'rate limit metric', nil
            it_behaves_like 'sampling decision', '-0'
          end
        end
      end
    end
  end

  describe 'single span sampling' do
    subject(:trace) do
      tracer.trace('unrelated.top_level', service: 'other-service') do
        tracer.trace('single.sampled_span', service: 'my-service') do
          tracer.trace('unrelated.child_span', service: 'not-service') {}
        end
      end
    end

    include_context 'agent-based test'

    before do
      Datadog.configure do |c|
        c.tracing.sampling.span_rules = json_rules if json_rules
        c.tracing.sampling.default_rate = trace_sampling_rate if trace_sampling_rate

        # Test setup
        c.tracing.sampler = custom_sampler if custom_sampler
      end

      WebMock.enable!

      trace # Run test subject
      wait_for_flush
    end

    let(:wait_for_flush) { try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 } }
    let(:trace_op) { @trace_op }
    let(:stats) { tracer.writer.stats }

    let(:custom_sampler) { nil }

    let(:trace_sampling_rate) { nil }
    let(:json_rules) { JSON.dump(rules) if rules }
    let(:rules) { nil }

    let(:spans) do
      expect(trace_segments).to have(1).item
      trace_segments[0].spans
    end

    let(:local_root_span) do
      spans.find { |x| x.parent_id == 0 } || spans[0]
    end

    let(:single_sampled_span) do
      single_sampled_spans = spans.select { |s| s.name == 'single.sampled_span' }
      expect(single_sampled_spans).to have(1).item
      single_sampled_spans[0]
    end

    after do
      WebMock.disable!
      Datadog.configuration.tracing.sampling.reset!
    end

    shared_examples 'does not modify spans' do
      it 'does not modify span sampling tags' do
        expect(spans).to_not include(have_tag('_dd.span_sampling.mechanism'))
        expect(spans).to_not include(have_tag('_dd.span_sampling.rule_rate'))
        expect(spans).to_not include(have_tag('_dd.span_sampling.max_per_second'))
      end

      it 'trace sampling decision is not set to simple span sampling' do
        expect(local_root_span.get_tag('_dd.p.dm')).to_not eq('-8')
      end
    end

    shared_examples 'set single span sampling tags' do
      it do
        expect(single_sampled_span.get_metric('_dd.span_sampling.mechanism')).to eq(8)
        expect(single_sampled_span.get_metric('_dd.span_sampling.rule_rate')).to eq(1.0)
        expect(single_sampled_span.get_metric('_dd.span_sampling.max_per_second')).to eq(-1)
        expect(local_root_span.get_tag('_dd.p.dm')).to eq('-8')
      end
    end

    shared_examples 'flushed complete trace' do |expected_span_count: 3|
      it_behaves_like 'flushed trace'

      it 'flushed all spans' do
        expect(spans).to have(expected_span_count).items
      end
    end

    context 'with default settings' do
      it_behaves_like 'flushed complete trace'
      it_behaves_like 'does not modify spans'
    end

    context 'with a kept trace' do
      let(:trace_sampling_rate) { 1.0 }

      it_behaves_like 'flushed complete trace'
      it_behaves_like 'does not modify spans'
    end

    context 'with a dropped trace' do
      context 'by priority sampling' do
        let(:trace_sampling_rate) { 0.0 }

        context 'with rule matching' do
          context 'with a dropped span' do
            let(:rules) { [{ name: 'single.sampled_span', sample_rate: 0.0 }] }

            it_behaves_like 'flushed complete trace'
            it_behaves_like 'does not modify spans'

            context 'by rate limiting' do
              let(:rules) { [{ name: 'single.sampled_span', sample_rate: 1.0, max_per_second: 0 }] }

              it_behaves_like 'flushed complete trace'
              it_behaves_like 'does not modify spans'
            end
          end

          context 'with a kept span' do
            let(:rules) { [{ name: 'single.sampled_span', sample_rate: 1.0 }] }

            # it_behaves_like 'flushed complete trace'
            it_behaves_like 'set single span sampling tags'
          end
        end
      end

      context 'ensures correct stats calculation in the agent' do
        it 'sets the Datadog-Client-Computed-Top-Level header to a non-empty value' do
          expect(WebMock)
            .to have_requested(:post, %r{/traces}).with(headers: { 'Datadog-Client-Computed-Top-Level' => /.+/ })
        end
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

          write.write('!') # Signals that this fork is ready
          sleep(5) # Should be interrupted
          exit! # Should not be reached, will skip shutdown hooks
        end

        # Wait for fork to get ready
        IO.select([read], [], [], 5) # 5 second timeout
        expect(read.getc).to eq('!') # Child process is ready

        # Kill the process
        write.close
        Process.kill('TERM', fork_id) rescue nil

        # Read and return any output
        read.read.tap do
          try_wait_until { Process.wait(fork_id, Process::WNOHANG) }
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

    it { expect(tracer.sampler).to respond_to(:update) }

    it do
      3.times do |i|
        tracer.trace('parent_span') do
          tracer.trace('child_span') do |_span, trace|
            # I want to keep the trace to which `child_span` belongs
            trace.sampling_priority = i
          end
        end

        try_wait_until(seconds: 2) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end

    context 'with agent rates' do
      before do
        WebMock.enable!
        stub_request(:post, %r{/v0.4/traces}).to_return(status: 200, body: service_rates.to_json)
      end

      after { WebMock.disable! }

      let(:service_rates) { { rate_by_service: { 'service:kept,env:' => 1.0, 'service:dropped,env:' => Float::MIN } } }

      let(:set_agent_rates!) do
        # Send span to receive response from "agent" with mocked service rates above.
        tracer.trace('send_trace_to_fetch_service_rates') {}
        try_wait_until(seconds: 2) { tracer.writer.stats[:traces_flushed] >= 1 }

        # Reset stats and collected segments before test starts
        tracer.writer.send(:reset_stats!)
        trace_segments.clear
      end

      context 'without DD_ENV set' do
        before { set_agent_rates! }

        context 'with a kept trace' do
          before do
            tracer.trace('kept.span', service: 'kept') {}
            try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
          end

          it_behaves_like 'priority sampled', 1.0
          it_behaves_like 'sampling decision', '-1'
        end

        context 'with a dropped span' do
          before do
            tracer.trace('dropped.span', service: 'dropped') {}
            try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
          end

          it_behaves_like 'priority sampled', 0.0
          it_behaves_like 'sampling decision', nil
        end
      end

      context 'with DD_ENV set' do
        before do
          Datadog.configure do |c|
            c.env = 'test'
          end

          set_agent_rates!
        end

        let(:service_rates) do
          { rate_by_service: { 'service:kept,env:test' => 1.0, 'service:dropped,env:' => Float::MIN } }
        end

        context 'with a span matching the environment rates' do
          before do
            tracer.trace('kept.span', service: 'kept') {}
            try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
          end

          it_behaves_like 'priority sampled', 1.0
          it_behaves_like 'sampling decision', '-1'
        end

        context 'with a span not matching the environment rates' do
          before do
            Datadog.configure { |c| c.env = 'not-matching' }

            tracer.trace('kept.span', service: 'kept') {}
            try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
          end

          it_behaves_like 'priority sampled', 1.0
          it_behaves_like 'sampling decision', '-0'
        end
      end
    end
  end

  describe 'manual sampling' do
    include_context 'agent-based test'

    context 'with a kept trace' do
      before do
        tracer.trace('span') { |_, trace| trace.keep! }
        try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
      end

      it_behaves_like 'priority sampled', 2.0
      it_behaves_like 'sampling decision', '-4'
    end

    context 'with a rejected trace' do
      it 'drops trace at application side' do
        expect(tracer.writer).to_not receive(:write)

        tracer.trace('span') do |_, trace|
          trace.reject!
          trace.sampled = false
        end
      end
    end

    context 'with a custom sampler class' do
      before do
        Datadog.configure do |c|
          c.tracing.sampler = custom_sampler
        end
      end

      let(:custom_sampler) do
        instance_double(Datadog::Tracing::Sampling::Sampler, sample!: double, sample_rate: double)
      end

      context 'that accepts a span' do
        before do
          expect(custom_sampler).to receive(:sample!) do |trace|
            trace.sampled = true
            false
          end
        end

        it 'flushes the span' do
          tracer.trace('span') {}
          try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
        end
      end

      context 'that rejects a span' do
        before do
          expect(custom_sampler).to receive(:sample!) do |trace|
            trace.sampled = false
            false
          end
        end

        it 'drops trace at application side' do
          expect(tracer.writer).to_not receive(:write)

          tracer.trace('span') {}
        end
      end
    end
  end

  shared_examples 'flushes traces with span events' do |native_span_events_support: true|
    context 'a trace with span events' do
      subject(:trace_with_event) do
        tracer.trace('parent_span') do |span|
          span.span_events << Datadog::Tracing::SpanEvent.new(
            'event_name',
            time_unix_nano: 123,
            attributes: { 'key' => 'value' }
          )
        end

        try_wait_until(seconds: 2) { tracer.writer.stats[:traces_flushed] >= 1 }
      end

      before do
        allow_any_instance_of(Datadog::Core::Remote::Transport::HTTP::Negotiation::Response)
          .to receive(:span_events).and_return(span_events_support)

        allow(encoder).to receive(:encode).and_wrap_original do |m, *args|
          encoded = m.call(*args)
          traces = encoder.decode(encoded)

          traces = traces['traces'].first if traces.is_a?(Hash) # For Transport::IO

          expect(traces).to have(1).item
          @flushed_trace = traces.first

          encoded
        end
      end

      let(:flushed_trace) { @flushed_trace }

      context 'with agent supporting native span events' do
        before do
          skip 'Environment does not support native span events' unless native_span_events_support
        end

        let(:span_events_support) { true }

        it 'flushes events using the span_events field' do
          trace_with_event

          expect(flushed_trace['meta']).to_not have_key('events')
          expect(flushed_trace['span_events']).to eq(
            [
              { 'name' => 'event_name',
                'time_unix_nano' => 123,
                'attributes' => { 'key' => {
                  'string_value' => 'value', 'type' => 0
                } }, }
            ]
          )
        end
      end

      context 'with agent not supporting native span events' do
        let(:span_events_support) { false }

        it 'flushes events using the span_events field' do
          trace_with_event

          expect(flushed_trace['meta']['events']).to eq(
            JSON.dump(
              [
                { 'name' => 'event_name',
                  'time_unix_nano' => 123,
                  'attributes' => { 'key' => 'value' } }
              ]
            )
          )
          expect(flushed_trace).to_not have_key('span_events')
        end
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

    let(:transport) { Datadog::Tracing::Transport::IO.default(out: out) }
    let(:out) { instance_double(IO) } # Dummy output so we don't pollute STDOUT

    before do
      Datadog.configure do |c|
        c.tracing.writer = writer
      end

      # Verify Transport::IO is configured
      expect(tracer.writer.transport).to be_a_kind_of(Datadog::Tracing::Transport::IO::Client)
      expect(tracer.writer.transport.encoder).to be(Datadog::Core::Encoding::JSONEncoder)

      # Verify sampler can receive agent rate updates
      expect(tracer.sampler).to respond_to(:update)

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
      tracer.trace('parent_span') do
        tracer.trace('child_span') {}
      end

      try_wait_until { tracer.writer.stats[:traces_flushed] >= 1 }
      stats = tracer.writer.stats

      expect(stats[:traces_flushed]).to eq(1)
      expect(stats[:transport].client_error).to eq(0)
      expect(stats[:transport].server_error).to eq(0)
      expect(stats[:transport].internal_error).to eq(0)

      expect(out).to have_received(:puts)
    end

    it_behaves_like 'flushes traces with span events', native_span_events_support: false do
      let(:encoder) { Datadog.send(:components).tracer.writer.transport.encoder }
    end
  end

  describe 'Transport::HTTP' do
    include_context 'agent-based test'

    let(:writer) { Datadog::Tracing::Writer.new(transport: transport) }
    let(:transport) { Datadog::Tracing::Transport::HTTP.default(agent_settings: test_agent_settings, logger: logger) }
    let(:logger) { logger_allowing_debug }

    before do
      Datadog.configure do |c|
        c.tracing.writer = writer
      end

      # Verify Transport::HTTP is configured
      expect(tracer.writer.transport).to be_a_kind_of(Datadog::Tracing::Transport::Traces::Transport)

      # Verify sampler can receive agent rate updates
      expect(tracer.sampler).to respond_to(:update)

      # Verify priority sampler is configured and rates are updated
      expect(tracer.sampler).to receive(:update)
        .with(kind_of(Hash), decision: '-1')
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

        try_wait_until(seconds: 2) { tracer.writer.stats[:traces_flushed] >= 1 }
        stats = tracer.writer.stats

        expect(stats[:traces_flushed]).to eq(1)
        expect(stats[:transport].client_error).to eq(0)
        expect(stats[:transport].server_error).to eq(0)
        expect(stats[:transport].internal_error).to eq(0)
      end
    end

    it_behaves_like 'flushes traces with span events' do
      let(:encoder) { Datadog.send(:components).tracer.writer.transport.current_api.encoder }
    end
  end

  describe 'fiber-local context' do
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

      it 'create one fiber-local context per tracer' do
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
        it 'create one fiber-local context per tracer per thread' do
          span = tracer.trace('test')
          context = tracer.send(:call_context)

          span2 = tracer2.trace('test2')
          context2 = tracer2.send(:call_context)

          Thread.new do
            thread_span = tracer.trace('thread_test')
            @fiber_context = tracer.send(:call_context)

            thread_span2 = tracer2.trace('thread_test2')
            @fiber_context2 = tracer2.send(:call_context)

            thread_span.finish
            thread_span2.finish
          end.join

          span2.finish
          span.finish

          expect([context, context2, @fiber_context, @fiber_context2].uniq)
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

  describe 'distributed tracing' do
    include_context 'agent-based test'

    [
      Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT,
      Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT,
      Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP,
      Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP,
    ].each do |priority|
      context "with sampling priority #{priority}" do
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '123',
            'HTTP_X_DATADOG_PARENT_ID' => '456',
            'HTTP_X_DATADOG_SAMPLING_PRIORITY' => priority.to_s,
            'HTTP_X_DATADOG_ORIGIN' => 'ci',
          }
        end

        before { Datadog.configure {} } # Ensure tracer is configured before calling `Contrib::HTTP.extract`

        it 'ensures trace is flushed' do
          trace_digest = Datadog::Tracing::Contrib::HTTP.extract(env)
          Datadog::Tracing.continue_trace!(trace_digest)

          tracer.trace('name') {}

          try_wait_until(seconds: 2) { tracer.writer.stats[:traces_flushed] >= 1 }

          stats = tracer.writer.stats
          expect(stats[:traces_flushed]).to eq(1)
          expect(stats[:transport].client_error).to eq(0)
          expect(stats[:transport].server_error).to eq(0)
          expect(stats[:transport].internal_error).to eq(0)
        end
      end
    end
  end
end
