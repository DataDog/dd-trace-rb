require 'spec_helper'
require 'datadog/core/crashtracking/component'

require 'webrick'
require 'fiddle'

RSpec.describe Datadog::Core::Crashtracking::Component,
  skip: Datadog::Core::Crashtracking::Component::LIBDATADOG_API_FAILURE do
    describe '.build' do
      let(:settings) { Datadog::Core::Configuration::Settings.new }
      let(:agent_settings) { double('agent_settings') }
      let(:logger) { Logger.new($stdout) }
      let(:tags) { {} }
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

          component = double('component')
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

          expect(described_class.build(settings, agent_settings, logger: logger)).to be_nil
        end
      end
    end

    context 'instance methods' do
      before do
        # No crash tracker process should still be running at the start of each testcase
        wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
      end

      after do
        # No crash tracker process should still be running at the end of each testcase
        wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
      end

      let(:logger) { Logger.new($stdout) }
      let(:agent_base_url) { 'http://localhost:6006' }

      let(:crashtracker_options) do
        {
          agent_base_url: agent_base_url,
          tags: { 'tag1' => 'value1', 'tag2' => 'value2' },
          path_to_crashtracking_receiver_binary: ::Libdatadog.path_to_crashtracking_receiver_binary,
          ld_library_path: ::Libdatadog.ld_library_path,
          logger: logger,
        }
      end

      subject(:crashtracker) { described_class.new(**crashtracker_options) }

      describe '#start' do
        context 'when _native_start_or_update_on_fork raises an exception' do
          it 'logs the exception' do
            expect(described_class).to receive(:_native_start_or_update_on_fork) { raise 'Test failure' }
            expect(logger).to receive(:error).with(/Failed to start crash tracking: Test failure/)

            crashtracker.start
          end
        end

        it 'starts the crash tracker' do
          crashtracker.start

          wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to_not be_empty

          crashtracker.stop
        end

        context 'when calling start multiple times in a row' do
          it 'only starts the crash tracker once' do
            3.times { crashtracker.start }

            wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 1

            crashtracker.stop
          end
        end

        context 'when called in a fork' do
          it 'starts a second crash tracker for the fork' do
            crashtracker.start

            expect_in_fork do
              wait_for { `pgrep -f libdatadog-crashtracking-receiver`.lines.size }.to be 2

              crashtracker.stop
            end

            crashtracker.stop
          end
        end
      end

      describe '#stop' do
        context 'when _native_stop_crashtracker raises an exception' do
          it 'logs the exception' do
            expect(described_class).to receive(:_native_stop) { raise 'Test failure' }
            expect(logger).to receive(:error).with(/Failed to stop crash tracking: Test failure/)

            crashtracker.stop
          end
        end

        it 'stops the crash tracker' do
          crashtracker.start

          crashtracker.stop

          wait_for { `pgrep -f libdatadog-crashtracking-receiver` }.to be_empty
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
              crashtracker.start

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

        context do
          it do
            allow(described_class).to receive(:_native_start_or_update_on_fork)

            crashtracker = build_crashtracker(agent_base_url: 'http://localhost:6001').tap(&:start)

            fork_expectations = proc do
              expect(described_class).to have_received(:_native_start_or_update_on_fork).with(
                hash_including(
                  action: :start,
                  exporter_configuration: [:agent, 'http://localhost:6001']
                )
              )
            end

            expect_in_fork(fork_expectations: fork_expectations) do
              allow(described_class).to receive(:_native_start_or_update_on_fork)
              build_crashtracker(agent_base_url: 'http://localhost:6002').tap(&:start)
            end

            crashtracker.stop
          end

          def build_crashtracker(options)
            described_class.new(
              agent_base_url: options[:agent_base_url],
              tags: {},
              path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary,
              ld_library_path: Libdatadog.ld_library_path,
              logger: Logger.new($stdout),
            )
          end
        end
      end
    end
  end
