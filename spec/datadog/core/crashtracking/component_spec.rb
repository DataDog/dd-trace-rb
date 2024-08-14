require 'spec_helper'
require 'datadog/core/crashtracking/component'

require 'webrick'
require 'fiddle'

RSpec.describe Datadog::Core::Crashtracking::Component,
  skip: !CrashtrackingHelpers.supported? do
    describe '.build' do
      let(:settings) { Datadog::Core::Configuration::Settings.new }
      let(:agent_settings) { double('agent_settings') }
      let(:logger) { Logger.new($stdout) }
      let(:tags) { { 'tag1' => 'value1' } }
      let(:agent_base_url) { 'agent_base_url' }
      let(:ld_library_path) { 'ld_library_path' }
      let(:path_to_crashtracking_receiver_binary) { 'path_to_crashtracking_receiver_binary' }

      context 'when all required parameters are provided' do
        it 'creates a new instance of Component and starts it' do
          expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
            .and_return(tags)
          expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings)
            .and_return(agent_base_url)
          expect(::Libdatadog).to receive(:ld_library_path)
            .and_return(ld_library_path)
          expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
            .and_return(path_to_crashtracking_receiver_binary)
          expect(logger).to_not receive(:warn)

          component = double(instance_double(described_class))
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

      context 'when missing `agent_base_url`' do
        let(:agent_base_url) { nil }

        it 'returns nil' do
          expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
            .and_return(tags)
          expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings)
            .and_return(agent_base_url)
          expect(::Libdatadog).to receive(:ld_library_path)
            .and_return(ld_library_path)
          expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
            .and_return(path_to_crashtracking_receiver_binary)
          expect(logger).to receive(:warn).with(/cannot enable crash tracking/)

          expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
        end
      end

      context 'when missing `ld_library_path`' do
        let(:ld_library_path) { nil }

        it 'returns nil' do
          expect(Datadog::Core::Crashtracking::TagBuilder).to receive(:call).with(settings)
            .and_return(tags)
          expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings)
            .and_return(agent_base_url)
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
          expect(Datadog::Core::Crashtracking::AgentBaseUrl).to receive(:resolve).with(agent_settings)
            .and_return(agent_base_url)
          expect(::Libdatadog).to receive(:ld_library_path)
            .and_return(ld_library_path)
          expect(::Libdatadog).to receive(:path_to_crashtracking_receiver_binary)
            .and_return(path_to_crashtracking_receiver_binary)
          expect(logger).to receive(:warn).with(/cannot enable crash tracking/)

          expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
        end
      end
    end

    context 'instance methods' do
      # No crash tracker process should still be running at the start of each testcase
      around do |example|
        wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
        example.run
        wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
      end

      describe '#start' do
        context 'when _native_start_or_update_on_fork raises an exception' do
          it 'logs the exception' do
            logger = Logger.new($stdout)
            crashtracker = build_crashtracker(logger: logger)

            expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
            expect(logger).to receive(:error).with(/Failed to start crash tracking: Test failure/)

            crashtracker.start
          end
        end

        it 'starts the crash tracker' do
          crashtracker = build_crashtracker

          crashtracker.start

          wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to_not be_empty

          tear_down!
        end

        context 'when calling start multiple times in a row' do
          it 'only starts the crash tracker once' do
            crashtracker = build_crashtracker

            3.times { crashtracker.start }

            wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 1

            tear_down!
          end
        end

        context 'when multiple instances' do
          it 'only starts the crash tracker once' do
            crashtracker = build_crashtracker
            crashtracker.start

            another_crashtracker = build_crashtracker
            another_crashtracker.start

            wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 1

            tear_down!
          end
        end

        context 'when forked' do
          it 'starts a second crash tracker for the fork' do
            crashtracker = build_crashtracker

            crashtracker.start

            expect_in_fork do
              wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 2
            end

            tear_down!
          end
        end
      end

      describe '#stop' do
        context 'when _native_stop_crashtracker raises an exception' do
          it 'logs the exception' do
            logger = Logger.new($stdout)
            crashtracker = build_crashtracker(logger: logger)

            expect(described_class).to receive(:_native_stop) { raise 'Test failure' }
            expect(logger).to receive(:error).with(/Failed to stop crash tracking: Test failure/)

            crashtracker.stop
          end
        end

        it 'stops the crash tracker' do
          crashtracker = build_crashtracker

          crashtracker.start

          wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to eq 1

          crashtracker.stop

          wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
        end
      end

      describe '#update_on_fork' do
        context 'when _native_stop_crashtracker raises an exception' do
          it 'logs the exception' do
            logger = Logger.new($stdout)
            crashtracker = build_crashtracker(logger: logger)

            expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
            expect(logger).to receive(:error).with(/Failed to update_on_fork crash tracking: Test failure/)

            crashtracker.update_on_fork
          end
        end

        it 'update_on_fork the crash tracker' do
          expect(described_class).to receive(:_native_start_or_update_on_fork).with(
            hash_including(action: :update_on_fork)
          )

          crashtracker = build_crashtracker

          crashtracker.update_on_fork
        end

        it 'updates existing crash tracking process after started' do
          crashtracker = build_crashtracker

          crashtracker.start
          crashtracker.update_on_fork

          wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 1

          tear_down!
        end
      end

      context 'integration testing' do
        shared_context 'HTTP server' do
          let(:server) do
            WEBrick::HTTPServer.new(
              Port: 0,
              Logger: log,
              AccessLog: access_log,
              StartCallback: -> { init_signal.push(1) }
            )
          end
          let(:hostname) { '127.0.0.1' }
          let(:log) { WEBrick::Log.new(StringIO.new, WEBrick::Log::WARN) }
          let(:access_log_buffer) { StringIO.new }
          let(:access_log) { [[access_log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]] }
          let(:server_proc) do
            proc do |req, res|
              messages << req.tap { req.body } # Read body, store message before socket closes.
              res.body = '{}'
            end
          end
          let(:init_signal) { Queue.new }

          let(:messages) { [] }

          before do
            server.mount_proc('/', &server_proc)
            @server_thread = Thread.new { server.start }
            init_signal.pop
          end

          after do
            unless RSpec.current_example.skipped?
              # When the test is skipped, server has not been initialized and @server_thread would be nil; thus we only
              # want to touch them when the test actually run, otherwise we would cause the server to start (incorrectly)
              # and join to be called on a nil @server_thread
              server.shutdown
              @server_thread.join
            end
          end
        end

        include_context 'HTTP server'

        let(:request) { messages.first }
        let(:port) { server[:Port] }

        let(:agent_base_url) { "http://#{hostname}:#{port}" }

        [:fiddle, :signal].each do |trigger|
          it "reports crashes via http when app crashes with #{trigger}" do
            fork_expectations = proc do |status:, stdout:, stderr:|
              expect(Signal.signame(status.termsig)).to eq('SEGV').or eq('ABRT')
              expect(stderr).to include('[BUG] Segmentation fault')
            end

            expect_in_fork(fork_expectations: fork_expectations) do
              crash_tracker = build_crashtracker(agent_base_url: agent_base_url)
              crash_tracker.start

              if trigger == :fiddle
                Fiddle.free(42)
              else
                Process.kill('SEGV', Process.pid)
              end
            end

            crash_report = JSON.parse(request.body, symbolize_names: true)[:payload].first

            expect(crash_report[:stack_trace]).to_not be_empty
            expect(crash_report[:tags]).to include('signum:11', 'signame:SIGSEGV')

            crash_report_message = JSON.parse(crash_report[:message], symbolize_names: true)

            expect(crash_report_message[:metadata]).to include(
              profiling_library_name: 'dd-trace-rb',
              profiling_library_version: Datadog::VERSION::STRING,
              family: 'ruby',
              tags: ['tag1:value1', 'tag2:value2'],
            )
            expect(crash_report_message[:files][:'/proc/self/maps']).to_not be_empty
            expect(crash_report_message[:os_info]).to_not be_empty
          end
        end

        context 'when forked' do
          # This integration test coverages the case that
          # the callback registered with `Utils::AtForkMonkeyPatch.at_fork`
          # does not contain a stale instance of the crashtracker component.
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
            end

            expect_in_fork do
              expect(described_class).to have_received(:_native_start_or_update_on_fork).with(
                hash_including(
                  action: :update_on_fork,
                  exporter_configuration: [:agent, 'http://google.com:9126/'],
                )
              )
            end
          end
        end
      end
    end

    def build_crashtracker(options = {})
      described_class.new(
        agent_base_url: options[:agent_base_url] || 'http://localhost:6006',
        tags: options[:tags] || { 'tag1' => 'value1', 'tag2' => 'value2' },
        path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary,
        ld_library_path: Libdatadog.ld_library_path,
        logger: options[:logger] || Logger.new($stdout),
      )
    end

    def tear_down!
      described_class._native_stop
    end
  end
