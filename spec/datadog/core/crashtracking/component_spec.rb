require 'spec_helper'
require 'datadog/core/crashtracking/component'

require 'webrick'
require 'fiddle'

RSpec.describe Datadog::Core::Crashtracking::Component, skip: !LibdatadogHelpers.supported? do
  let(:logger) { Logger.new($stdout) }

  describe '.build' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:agent_settings) do
      instance_double(Datadog::Core::Configuration::AgentSettings)
    end
    let(:tags) { {'tag1' => 'value1'} }
    let(:agent_base_url) { 'agent_base_url' }
    let(:ld_library_path) { 'ld_library_path' }
    let(:path_to_crashtracking_receiver_binary) { 'path_to_crashtracking_receiver_binary' }

    context 'when all required parameters are provided' do
      it 'creates a new instance of Component and starts it' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
          .and_return(tags)
        expect(agent_settings).to receive(:url).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path)
          .and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
          .and_return(path_to_crashtracking_receiver_binary)
        expect(logger).to_not receive(:warn)

        component = instance_double(described_class)
        expect(described_class).to receive(:new).with(
          tags: tags,
          agent_base_url: agent_base_url,
          ld_library_path: ld_library_path,
          path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
          logger: logger
        ).and_return(component)

        expect(component).to receive(:start)

        described_class.build(settings, agent_settings, logger: logger)
      end
    end

    context 'when missing `ld_library_path`' do
      let(:ld_library_path) { nil }

      it 'returns nil' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
          .and_return(tags)
        expect(agent_settings).to receive(:url).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path)
          .and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
          .and_return(path_to_crashtracking_receiver_binary)
        expect(logger).to receive(:warn).with(/cannot enable crash tracking/)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
      end
    end

    context 'when missing `path_to_crashtracking_receiver_binary`' do
      let(:path_to_crashtracking_receiver_binary) { nil }

      it 'returns nil' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
          .and_return(tags)
        expect(agent_settings).to receive(:url).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path)
          .and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
          .and_return(path_to_crashtracking_receiver_binary)
        expect(logger).to receive(:warn).with(/cannot enable crash tracking/)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
      end
    end

    context 'when agent_base_url is invalid (e.g. hostname is an IPv6 address)' do
      let(:agent_base_url) { 'http://1234:1234::1/' }

      it 'returns an instance of Component that failed to start' do
        expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
          .and_return(tags)
        expect(agent_settings).to receive(:url).and_return(agent_base_url)
        expect(::Libdatadog).to receive(:ld_library_path)
          .and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
          .and_return(path_to_crashtracking_receiver_binary)

        # Diagnostics is only provided via the error report to logger,
        # there is no indication in the object state that it failed to start.
        expect(logger).to receive(:error).with(/Failed to start crash tracking/)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_a(described_class)
      end
    end
  end

  context 'instance methods' do
    shared_context 'HTTP server' do
      http_server do |http_server|
        http_server.mount_proc('/', &server_proc)
      end
      let(:hostname) { '127.0.0.1' }
      let(:server_proc) do
        proc do |req, res|
          messages << req.tap { req.body } # read body, store message before socket closes.
          res.body = '{}'
        end
      end
      let(:messages) { [] }
    end

    describe '#start' do
      context 'when _native_start_or_update_on_fork raises an exception' do
        it 'logs the exception' do
          crashtracker = build_crashtracker(logger: logger)

          expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
          expect(logger).to receive(:error).with(/Failed to start crash tracking: Test failure/)

          crashtracker.start
        end
      end
    end

    describe '#stop' do
      context 'when _native_stop_crashtracker raises an exception' do
        it 'logs the exception' do
          crashtracker = build_crashtracker(logger: logger)

          expect(described_class).to receive(:_native_stop) { raise 'Test failure' }
          expect(logger).to receive(:error).with(/Failed to stop crash tracking: Test failure/)

          crashtracker.stop
        end
      end
    end

    describe '#report_unhandled_exception' do
      include_context 'HTTP server'

      let(:agent_base_url) { "http://#{hostname}:#{http_server_port}" }

      # exception only gets stack attached when raised
      def method_that_raises
        raise StandardError, 'Test unhandled exception with backtrace'
      end

      it 'reports the unhandled exception' do
        crashtracker = build_crashtracker(agent_base_url: agent_base_url, logger: logger)
        exception =
          begin
            method_that_raises
          rescue => e
            e
          end

        crashtracker.report_unhandled_exception(exception)

        # Wait for both crash ping and crash report to be sent
        try_wait_until { messages.length == 2 }

        parsed_messages = messages.map { |msg| JSON.parse(msg.body.to_s, symbolize_names: true) }

        # Don't assume order on network requests
        # We send crash ping first, but it is sent in separate requests
        # We are not guaranteed the order of the messages received in the array
        #
        # Find crash ping message (should have is_crash_ping:true tag)
        crash_ping_message = parsed_messages.find do |msg|
          payload = msg[:payload].first
          payload[:tags]&.include?('is_crash_ping:true')
        end
        expect(crash_ping_message).to_not be_nil

        # Find crash report message (should have is_crash:true)
        crash_report_message = parsed_messages.find do |msg|
          payload = msg[:payload].first
          payload[:is_crash] == true
        end

        # Verify crash report content
        crash_payload = crash_report_message[:payload].first
        crash_report = JSON.parse(crash_payload[:message], symbolize_names: true)

        # Verify metadata (ddog_crasht_CrashInfoBuilder_with_metadata)
        expect(crash_report[:metadata]).to include(
          library_name: 'dd-trace-rb',
          library_version: Datadog::VERSION::STRING,
          family: 'ruby'
        )
        expect(crash_report[:metadata][:tags]).to be_an(Array)
        expect(crash_report[:metadata][:tags]).to_not be_empty

        # Verify error kind is unhandled exception (ddog_crasht_CrashInfoBuilder_with_kind)
        expect(crash_report[:error][:kind]).to eq('UnhandledException')

        # Verify process info is present (ddog_crasht_CrashInfoBuilder_with_proc_info)
        expect(crash_report[:proc_info][:pid]).to be > 0

        # Verify OS info is present (ddog_crasht_CrashInfoBuilder_with_os_info_this_machine)
        # should not be unknown os_info
        expect(crash_report[:os_info][:architecture]).to_not eq('unknown')

        # Verify exception message format (ddog_crasht_CrashInfoBuilder_with_message)
        expect(crash_report[:error][:message]).to eq(
          "Process was terminated due to an unhandled exception of type 'StandardError'. Message: \"Test unhandled exception with backtrace\""
        )

        # Verify stack trace is present (ddog_crasht_CrashInfoBuilder_with_stack)
        stack_frames = crash_report[:error][:stack][:frames]
        exception_backtrace = exception.backtrace_locations
        expect(stack_frames).to be_an(Array)
        expect(stack_frames.length).to be > 0
        expect(crash_report[:error][:stack][:incomplete]).to be false

        # Verify that the stack frames match the exception backtrace
        (0..stack_frames.length - 1).each do |i|
          expect(stack_frames[i][:function]).to eq(exception_backtrace[i].label)
          expect(stack_frames[i][:file]).to eq(exception_backtrace[i].path)
          expect(stack_frames[i][:line]).to eq(exception_backtrace[i].lineno)
        end
      end
    end

    describe '#update_on_fork' do
      before { allow(logger).to receive(:debug) }

      context 'when _native_stop_crashtracker raises an exception' do
        it 'logs the exception' do
          crashtracker = build_crashtracker(logger: logger)

          expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
          expect(logger).to receive(:error).with(/Failed to update_on_fork crash tracking: Test failure/)

          crashtracker.update_on_fork
        end
      end

      it 'updates the crash tracker' do
        expect(described_class).to receive(:_native_start_or_update_on_fork).with(
          hash_including(action: :update_on_fork)
        )

        crashtracker = build_crashtracker(logger: logger)

        crashtracker.update_on_fork
      end

      it 'refreshes the latest settings' do
        allow(Datadog).to receive(:configuration).and_return(:latest_settings)
        allow(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(:latest_settings).and_return([:latest_tags])

        expect(described_class).to receive(:_native_start_or_update_on_fork).with(
          hash_including(tags_as_array: [:latest_tags])
        )

        crashtracker = build_crashtracker(logger: logger)

        crashtracker.update_on_fork
      end
    end

    context 'integration testing' do
      include_context 'HTTP server'

      let(:request) do
        # first message is a ping
        messages[1]
      end

      let(:agent_base_url) { "http://#{hostname}:#{http_server_port}" }
      let(:fork_expectations) do
        proc do |status:, stdout:, stderr:|
          expect(status.termsig).to_not be_nil
          expect(Signal.signame(status.termsig)).to eq('SEGV').or eq('ABRT')
          expect(stderr).to include('[BUG] Segmentation fault')
        end
      end

      let(:parsed_request) { JSON.parse(request.body, symbolize_names: true) }
      let(:crash_report) { parsed_request.fetch(:payload).fetch(:logs).first }
      let(:crash_report_message) { JSON.parse(crash_report.fetch(:message), symbolize_names: true) }
      let(:crash_report_experimental) { crash_report_message.fetch(:experimental) }
      let(:stack_trace) { crash_report_message.fetch(:error).fetch(:stack).fetch(:frames) }

      # NOTE: If any of these tests seem flaky, the `upload_timeout_seconds` may need to be raised (or otherwise
      # we need to tweak libdatadog to not need such high timeouts).

      [
        [:fiddle, 'rb_fiddle_free', proc { Fiddle.free(42) }],
        [:signal, 'rb_f_kill', proc { Process.kill('SEGV', Process.pid) }],
      ].each do |trigger_name, function, trigger|
        it "reports crashes via http when app crashes with #{trigger_name}" do
          expect_in_fork(fork_expectations: fork_expectations, timeout_seconds: 15) do
            crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
            crash_tracker.start
            trigger.call
          end
          expect(stack_trace).to match(array_including(hash_including(function: function)))
          expect(stack_trace.size).to be > 10
          expect(crash_report[:tags]).to include('si_signo:11', 'si_signo_human_readable:SIGSEGV')

          expect(crash_report_message[:metadata]).to include(
            library_name: 'dd-trace-rb',
            library_version: Datadog::VERSION::STRING,
            family: 'ruby',
            tags: ['tag1:value1', 'tag2:value2', 'language:ruby-testing-123', 'service:ruby-testing-123'],
          )
          expect(crash_report_message[:files][:"/proc/self/maps"]).to_not be_empty
          expect(crash_report_message[:os_info]).to_not be_empty
          expect(parsed_request.fetch(:application)).to include(
            service_name: 'ruby-testing-123',
            language_name: 'ruby-testing-123',
          )
        end
      end

      context 'Ruby unhandled exception crash reporting' do
        let(:ruby_crash_expectations) do
          proc do |status:, stdout:, stderr:|
            # ruby exceptions should exit with status 1, not signal termination
            expect(status.exitstatus).to eq(1)
          end
        end

        it 'gets triggered by at_exit hook, which reports the exception via http' do
          expect_in_fork(fork_expectations: ruby_crash_expectations, timeout_seconds: 15) do
            # Configure Datadog so the at_exit hook can find the crashtracker
            Datadog.configure do |c|
              c.agent.host = '127.0.0.1'
              c.agent.port = http_server_port
            end

            raise StandardError, 'Test Ruby unhandled exception'
          end

          # check that both crash ping and crash report were sent
          # Content is checked in unit test
          expect(messages.length).to eq(2)
        end
      end

      it 'picks up the latest settings when reporting a crash' do
        expect_in_fork(fork_expectations: fork_expectations, timeout_seconds: 15) do
          expect(logger).to_not receive(:error)

          crash_tracker = build_crashtracker(agent_base_url: 'http://example.com:6006', logger: logger)
          crash_tracker.start
          crash_tracker.stop

          crash_tracker = build_crashtracker(
            agent_base_url: agent_base_url,
            tags: {'latest_settings' => 'included'},
            logger: logger
          )
          crash_tracker.start

          Fiddle.free(42)
        end

        expect(crash_report_message[:metadata]).to include(
          library_name: 'dd-trace-rb',
          library_version: Datadog::VERSION::STRING,
          family: 'ruby',
          tags: ['latest_settings:included'],
        )
      end

      context 'via unix domain socket' do
        define_http_server_uds do |http_server|
          http_server.mount_proc('/', &server_proc)
        end

        it 'reports crashes via uds when app crashes with fiddle' do
          expect_in_fork(fork_expectations: fork_expectations, timeout_seconds: 15) do
            crash_tracker = build_crashtracker(agent_base_url: uds_agent_base_url)
            crash_tracker.start

            Fiddle.free(42)
          end

          expect(stack_trace).to_not be_empty
          expect(crash_report[:tags]).to include('si_signo:11', 'si_signo_human_readable:SIGSEGV')

          expect(crash_report_message[:metadata]).to_not be_empty
          expect(crash_report_message[:files][:"/proc/self/maps"]).to_not be_empty
          expect(crash_report_message[:os_info]).to_not be_empty
        end
      end

      context 'when forked' do
        # This tests that the callback registered with `Utils::AtForkMonkeyPatch.at_fork`
        # does not contain a stale instance of the crashtracker component.

        reset_at_fork_monkey_patch_for_components!

        # Avoid triggering warnings from the agent settings resolver when these are set in the testing environment
        with_env 'DD_AGENT_HOST' => nil, 'DD_TRACE_AGENT_PORT' => nil

        after do
          Datadog.configuration.reset!
        end

        it 'ensures the latest configuration applied' do
          allow(described_class).to receive(:_native_start_or_update_on_fork)

          # `Datadog.configure` to trigger crashtracking component reinstantiation,
          #  a callback is first registered with `Utils::AtForkMonkeyPatch.at_fork`,
          #  but not with the second `Datadog.configure` invokation.
          Datadog.configure do |c|
            c.agent.host = 'example.com'
          end

          Datadog.configure do |c|
            c.agent.host = 'google.com'
            c.agent.port = 12345
          end

          expect_in_fork do
            expect(described_class).to have_received(:_native_start_or_update_on_fork).with(
              hash_including(
                action: :update_on_fork,
                agent_base_url: 'http://google.com:12345/',
              )
            )
          end
        end
      end

      describe 'Ruby and C method runtime stack capture' do
        let(:runtime_stack) { crash_report_experimental[:runtime_stack] }

        before do
          raise 'This spec requires profiling (native extension not available)' unless Datadog::Profiling.supported?
        end

        it 'captures both Ruby and C method frames in mixed stacks' do
          expect_in_fork(fork_expectations: fork_expectations, timeout_seconds: 15) do
            crash_stack_helper_class = Class.new do
              def top_level_ruby_method
                ruby_method_with_c_calls
              end

              def ruby_method_with_c_calls
                'hello world'.gsub('world') do |_match|
                  {a: 1, b: 2}.each do |_key, _value|
                    Fiddle.free(42)
                  end
                end
              end
            end

            crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
            crash_tracker.start

            crash_stack_helper_class.new.top_level_ruby_method
          end

          expect(runtime_stack).to be_a(Hash)
          frames = runtime_stack[:frames]

          # Check that the crashing function is captured
          expect(frames).to include(
            hash_including(
              function: 'free'
            )
          )

          # Sanity check some frames
          expect(frames).to include(
            hash_including(
              function: 'ruby_method_with_c_calls'
            )
          )

          expect(frames).to include(
            hash_including(
              function: 'top_level_ruby_method'
            )
          )

          expect(frames).to include(
            hash_including(
              function: 'each'
            )
          )

          expect(frames).to include(
            hash_including(
              function: 'gsub'
            )
          )
        end
      end
    end
  end

  def build_crashtracker(**options)
    testing_string = 'ruby-testing-123'
    described_class.new(
      agent_base_url: options[:agent_base_url] || 'http://localhost:6006',
      tags: options[:tags] ||
        {'tag1' => 'value1', 'tag2' => 'value2', 'language' => testing_string, 'service' => testing_string},
      path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary,
      ld_library_path: Libdatadog.ld_library_path,
      logger: options[:logger] || Logger.new($stdout),
    )
  end

  def tear_down!
    described_class._native_stop
  end
end
