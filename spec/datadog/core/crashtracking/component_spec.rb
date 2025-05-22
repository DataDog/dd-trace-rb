require 'spec_helper'
require 'datadog/core/crashtracking/component'

require 'webrick'
require 'fiddle'

RSpec.describe Datadog::Core::Crashtracking::Component, skip: !LibdatadogHelpers.supported? do
  let(:logger) { Logger.new($stdout) }

  describe '.build' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }
    let(:agent_settings) do
      instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings)
    end
    let(:tags) { { 'tag1' => 'value1' } }
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

      let(:request) { messages.first }

      let(:agent_base_url) { "http://#{hostname}:#{http_server_port}" }

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
          expect(crash_report[:tags]).to include('si_signo:11', 'si_signo_human_readable:SIGSEGV')

          crash_report_message = JSON.parse(crash_report[:message], symbolize_names: true)

          expect(crash_report_message[:metadata]).to include(
            library_name: 'dd-trace-rb',
            library_version: Datadog::VERSION::STRING,
            family: 'ruby',
            tags: ['tag1:value1', 'tag2:value2'],
          )
          expect(crash_report_message[:files][:'/proc/self/maps']).to_not be_empty
          expect(crash_report_message[:os_info]).to_not be_empty
        end
      end

      context 'via unix domain socket' do
        define_http_server_uds do |http_server|
          http_server.mount_proc('/', &server_proc)
        end

        it 'reports crashes via uds when app crashes with fiddle' do
          fork_expectations = proc do |status:, stdout:, stderr:|
            expect(Signal.signame(status.termsig)).to eq('SEGV').or eq('ABRT')
            expect(stderr).to include('[BUG] Segmentation fault')
          end

          expect_in_fork(fork_expectations: fork_expectations) do
            crash_tracker = build_crashtracker(agent_base_url: uds_agent_base_url)
            crash_tracker.start

            Fiddle.free(42)
          end

          crash_report = JSON.parse(request.body, symbolize_names: true)[:payload].first

          expect(crash_report[:stack_trace]).to_not be_empty
          expect(crash_report[:tags]).to include('si_signo:11', 'si_signo_human_readable:SIGSEGV')

          crash_report_message = JSON.parse(crash_report[:message], symbolize_names: true)

          expect(crash_report_message[:metadata]).to_not be_empty
          expect(crash_report_message[:files][:'/proc/self/maps']).to_not be_empty
          expect(crash_report_message[:os_info]).to_not be_empty
        end
      end

      context 'when forked' do
        # This tests that the callback registered with `Utils::AtForkMonkeyPatch.at_fork`
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
