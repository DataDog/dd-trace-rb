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
          .at_least(:once).and_return(ld_library_path)
        expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
          .at_least(:once).and_return(path_to_crashtracking_receiver_binary)

        # diagnostics is only provided via the error report to logger,
        # there is no indication in the object state that it failed to start.
        expect(logger).to receive(:error).with(/Failed to start crash tracking/)

        expect(described_class.build(settings, agent_settings, logger: logger)).to be_a(described_class)
      end
    end
  end

  context 'instance methods' do
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

    describe 'Ruby exception crash reporting' do
      shared_context 'Ruby exception HTTP server' do
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

      include_context 'Ruby exception HTTP server'

      let(:ruby_exception_request) do
        # find the crash report messages
        messages.find { |msg| msg.body&.include?('UnhandledException') || msg.body&.include?('is_crash') }
      end

      let(:agent_base_url) { "http://#{hostname}:#{http_server_port}" }
      let(:ruby_crash_expectations) do
        proc do |status:, stdout:, stderr:|
          # ruby exceptions should exit with status 1, not signal termination
          expect(status.exitstatus).to eq(1)
        end
      end

      [
        [:standard_error, 'StandardError', proc { raise StandardError, 'Test Ruby crash' }],
        [:runtime_error, 'RuntimeError', proc { raise 'Test runtime crash' }],
        [:custom_error, 'ArgumentError', proc { raise ArgumentError, 'Test argument crash' }],
      ].each do |trigger_name, exception_class, trigger|
        it "reports Ruby exceptions via http when app crashes with #{trigger_name}" do
          expect_in_fork(fork_expectations: ruby_crash_expectations, timeout_seconds: 15) do
            crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
            crash_tracker.start
            sleep 0.1
            trigger.call
          end

          # check that a crash report was sent
          expect(ruby_exception_request).to_not be_nil,
            "Expected crash report HTTP request but none was received. Messages: #{messages.map(&:path)}"

          if ruby_exception_request
            # parse the telemetry transport format
            parsed_telemetry = JSON.parse(ruby_exception_request.body.to_s, symbolize_names: true)
            expect(parsed_telemetry).to include(:api_version, :payload, :request_type)
            expect(parsed_telemetry[:request_type]).to eq('logs')

            # extract the crash report from the payload
            payload_item = parsed_telemetry[:payload].first
            puts "payload_item: #{payload_item[:message]}"
            expect(payload_item).to include(:message, :is_crash)
            expect(payload_item[:is_crash]).to be true

            # parse the crash report JSON from the message
            crash_report = JSON.parse(payload_item[:message], symbolize_names: true)
            expect(crash_report).to include(:metadata, :error, :timestamp)

            # validate exception details
            error_info = crash_report[:error]
            expect(error_info).to include(:kind, :message, :stack)
            expect(error_info[:kind]).to eq('UnhandledException')
            expect(error_info[:message]).to include(exception_class)

            # validate metadata
            metadata = crash_report[:metadata]
            expect(metadata).to include(
              :library_name,
              :library_version,
              :family,
              :tags
            )
            expect(metadata[:library_name]).to eq('dd-trace-rb')
            expect(metadata[:family]).to eq('ruby')

            # validate stack trace
            stack_frames = error_info[:stack][:frames]
            expect(stack_frames).to be_an(Array)
            expect(stack_frames.length).to be > 0

            # should contain our test trigger in the stack
            expect(stack_frames.any? { |frame| frame[:function]&.include?('block (4 levels) in') }).to be true
          end
        end
      end

      it 'does not report SystemExit as crashes' do
        expect_in_fork(
          fork_expectations: proc { |status:, stdout:, stderr:|
            # systemExit should not be reported as crash
            expect(status.exitstatus).to eq(42) # Custom exit status
          },
          timeout_seconds: 10
        ) do
          crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
          crash_tracker.start
          sleep 0.1
          exit(42) # should not be reported as crash
        end

        expect(messages.length).to eq(0), 'Expected no crash reports for SystemExit'
      end

      it 'does not report Interrupt as crashes' do
        expect_in_fork(
          fork_expectations: proc { |status:, stdout:, stderr:|
            # interrupt should not be reported as crash
            # process may exit normally or be terminated by signal depending on timing
            expect(Signal.signame(status.termsig)).to eq('INT') if status.termsig
          },
          timeout_seconds: 10
        ) do
          crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
          crash_tracker.start
          sleep 0.1
          Process.kill('INT', Process.pid) # should not be reported as crash
        end

        expect(messages.length).to eq(0), 'Expected no crash reports for Interrupt'
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
      shared_context 'HTTP server' do
        http_server do |http_server|
          http_server.mount_proc('/', &server_proc)
        end
        let(:hostname) { '127.0.0.1' }
        let(:server_proc) do
          proc do |req, res|
            messages << req.tap { req.body } # Read body, store message before socket closes.
            res.body = '{}'
          end
        end
        let(:init_signal) { Queue.new }

        let(:messages) { [] }
      end

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
      let(:crash_report) { parsed_request.fetch(:payload).first }
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

        # Avoid triggering warnings from the agent settings resolver when these are set in the testing environment
        with_env 'DD_AGENT_HOST' => nil, 'DD_TRACE_AGENT_PORT' => nil

        before do
          # Unit tests for at fork monkey patch module reset its state,
          # including the defined handlers.
          # We need to make sure that our handler is added to the list,
          # because normally it would be added during library initialization
          # and if the fork monkey patch test runs before this test,
          # the handler would get cleared out.
          Datadog::Core::Configuration::Components.const_get(:AT_FORK_ONLY_ONCE).send(:reset_ran_once_state_for_tests)

          # We also need to clear out the handlers because we could have
          # our own handler registered from the library initialization time,
          # if the at fork monkey patch did not run before this test.
          # In this case the handler would be executed twice which is
          # 1) probably not good and 2) would fail our assertions.
          Datadog::Core::Utils::AtForkMonkeyPatch.const_get(:AT_FORK_CHILD_BLOCKS).clear
        end

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
