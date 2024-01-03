# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/diagnostics/environment_logger'
require 'datadog/tracing/transport/io'

RSpec.describe Datadog::Tracing::Diagnostics::EnvironmentLogger do
  around { |example| ClimateControl.modify(environment) { example.run } }

  subject(:env_logger) { described_class }

  # Reading DD_AGENT_HOST allows this to work in CI
  let(:agent_hostname) { ENV['DD_AGENT_HOST'] || '127.0.0.1' }
  let(:agent_port) { ENV['DD_TRACE_AGENT_PORT'] || 8126 }

  let(:environment) { {} }

  before do
    # Resets "only-once" execution pattern of `collect_and_log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#collect_and_log!' do
    subject(:collect_and_log!) { env_logger.collect_and_log! }

    let(:logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(env_logger).to receive(:rspec?).and_return(false) # Allow rspec to log for testing purposes
      allow(Datadog).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug?).and_return true
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
    end

    it 'with default tracing settings' do
      collect_and_log!
      expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - TRACING') do |msg|
        json = JSON.parse(msg.partition('- TRACING -')[2].strip)
        expect(json).to match(
          'enabled' => true,
          'agent_url' => start_with("http://#{agent_hostname}:#{agent_port}?timeout="),
          'analytics_enabled' => false,
          'sample_rate' => nil,
          'sampling_rules' => nil,
          'integrations_loaded' => nil,
          'partial_flushing_enabled' => false,
        )
      end
    end

    context 'with multiple invocations' do
      it 'executes only once' do
        env_logger.collect_and_log!
        env_logger.collect_and_log!

        expect(logger).to have_received(:info).once
      end
    end

    context 'with agent error' do
      subject(:collect_and_log!) { env_logger.collect_and_log!(responses: [response]) }

      before { allow(logger).to receive(:warn) }

      let(:response) { Datadog::Core::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

      it do
        collect_and_log!
        expect(logger).to have_received(:warn).with start_with('DATADOG ERROR - TRACING - ') do |msg|
          error_line = msg.partition('- TRACING -')[2].strip
          error = error_line.partition(':')[2].strip

          expect(error_line).to start_with('Agent Error')
          expect(error).to include('ZeroDivisionError')
          expect(error).to include('msg')
        end
      end
    end

    context 'under a REPL' do
      around do |example|
        begin
          original = $PROGRAM_NAME
          $0 = 'irb'
          example.run
        ensure
          $0 = original
        end
      end

      context 'with default settings' do
        before do
          allow(env_logger).to receive(:rspec?).and_return(true) # Prevent rspec from logging
        end

        it do
          collect_and_log!
          expect(logger).to_not have_received(:info)
        end
      end

      context 'with explicit setting' do
        before do
          allow(Datadog.configuration.diagnostics.startup_logs).to receive(:enabled).and_return(true)
        end

        it do
          collect_and_log!
          expect(logger).to have_received(:info).with(/DATADOG CONFIGURATION - TRACING -/).once
        end
      end
    end

    context 'with error collecting information' do
      before do
        expect(Datadog::Tracing::Diagnostics::EnvironmentCollector).to receive(:collect_config!).and_raise
      end

      it 'rescues error and logs exception' do
        collect_and_log!
        expect(logger).to have_received(:warn).with start_with('Failed to collect tracing environment information')
      end
    end
  end

  describe Datadog::Tracing::Diagnostics::EnvironmentCollector do
    describe '#collect_config!' do
      subject(:collect_config!) { collector.collect_config! }

      let(:collector) { described_class }

      it 'with a default tracer' do
        is_expected.to match(
          enabled: true,
          agent_url: start_with("http://#{agent_hostname}:#{agent_port}?timeout="),
          analytics_enabled: false,
          sample_rate: nil,
          sampling_rules: nil,
          integrations_loaded: nil,
          partial_flushing_enabled: false,
        )
      end

      context 'with tracer disabled' do
        before { allow(Datadog.configuration.tracing).to receive(:enabled).and_return(false) }

        it { is_expected.to include enabled: false }
      end

      context 'with IO transport' do
        before do
          expect(Datadog.configuration.tracing).to receive(:writer).and_return(
            Datadog::Tracing::SyncWriter.new(
              transport: Datadog::Tracing::Transport::IO.default
            )
          )
        end

        it { is_expected.to include agent_url: nil }
      end

      context 'with unix socket transport' do
        let(:environment) do
          environment = {}

          environment['DD_AGENT_HOST'] = nil
          environment['DD_TRACE_AGENT_PORT'] = nil
          environment['DD_TRACE_AGENT_URL'] = nil
          environment['DD_TRACE_AGENT_UDS_PATH'] = '/tmp/trace.sock'

          environment
        end

        it { is_expected.to include agent_url: include('unix') }
        it { is_expected.to include agent_url: include('/tmp/trace.sock') }
      end

      context 'with analytics enabled' do
        before { expect(Datadog.configuration.tracing.analytics).to receive(:enabled).and_return(true) }

        it { is_expected.to include analytics_enabled: true }
      end

      context 'with integrations loaded' do
        before { Datadog.configure { |c| c.tracing.instrument :http, options } }

        let(:options) { {} }

        it { is_expected.to include integrations_loaded: start_with('http') }

        it do
          # Because net/http is default gem, we use the Ruby version as the library version.
          is_expected.to include integrations_loaded: end_with("@#{RUBY_VERSION}")
        end

        context 'with integration-specific settings' do
          let(:options) { { service_name: 'my-http' } }

          it { is_expected.to include integration_http_analytics_enabled: 'false' }
          it { is_expected.to include integration_http_analytics_sample_rate: '1.0' }
          it { is_expected.to include integration_http_service_name: 'my-http' }
          it { is_expected.to include integration_http_distributed_tracing: 'true' }
          it { is_expected.to include integration_http_split_by_domain: 'false' }
        end

        context 'with a complex setting value' do
          let(:options) { { service_name: Class.new } }

          it 'converts to a string' do
            is_expected.to include integration_http_service_name: start_with('#<Class:')
          end
        end

        context 'with partial flushing enabled' do
          before { expect(Datadog.configuration.tracing.partial_flush).to receive(:enabled).and_return(true) }

          it { is_expected.to include partial_flushing_enabled: true }
        end
      end
    end

    describe '#collect_errors!' do
      subject(:collect_errors!) { collector.collect_errors!([response]) }

      let(:collector) { described_class }
      let(:response) { instance_double(Datadog::Core::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to match(
          agent_error: nil
        )
      end

      context 'with agent connectivity issues' do
        let(:response) { Datadog::Core::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

        it { is_expected.to include agent_error: include('ZeroDivisionError') }
        it { is_expected.to include agent_error: include('msg') }
      end
    end
  end
end
