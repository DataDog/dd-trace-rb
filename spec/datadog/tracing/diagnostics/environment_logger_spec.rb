require 'spec_helper'
require 'datadog/core/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Tracing::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  # Reading DD_AGENT_HOST allows this to work in CI
  let(:agent_hostname) { ENV['DD_AGENT_HOST'] || '127.0.0.1' }
  let(:agent_port) { ENV['DD_TRACE_AGENT_PORT'] || 8126 }

  before do
    allow(DateTime).to receive(:now).and_return(DateTime.new(2020))

    # Resets "only-once" execution pattern of `log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#prefix' do
    it 'for tracing settings' do
      expect(logger).to have_received(:info).with include('TRACING')
    end
  end

  describe '#log_agent_errors!' do
    subject(:log_agent_errors!) { env_logger.log_agent_errors!([response]) }

    let(:logger) do
      log_agent_errors!
      tracer_logger
    end

    let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }
    let(:tracer_logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(Datadog).to receive(:logger).and_return(tracer_logger)
      allow(tracer_logger).to receive(:debug?).and_return true
      allow(tracer_logger).to receive(:debug)
      allow(tracer_logger).to receive(:info)
      allow(tracer_logger).to receive(:warn)
      allow(tracer_logger).to receive(:error)
    end

    context 'with multiple invocations' do
      it 'executes only once' do
        env_logger.log!([response])
        env_logger.log!([response])

        expect(logger).to have_received(:info).once
      end
    end

    context 'with agent error' do
      before { allow(tracer_logger).to receive(:warn) }

      let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

      it do
        expect(logger).to have_received(:warn).with start_with('DATADOG DIAGNOSTIC') do |msg|
          error_line = msg.partition('-')[2].strip
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
        it { expect(logger).to_not have_received(:info) }
      end

      context 'with explicit setting' do
        before do
          Datadog.configure { |c| c.diagnostics.startup_logs.enabled = true }
        end

        it { expect(logger).to have_received(:info) }
      end
    end

    context 'with error collecting information' do
      before do
        allow(tracer_logger).to receive(:warn)
        expect_any_instance_of(Datadog::Core::Diagnostics::EnvironmentCollector).to receive(:collect!).and_raise
      end

      it 'rescues error and logs exception' do
        expect(logger).to have_received(:warn).with start_with('Failed to collect environment information')
      end
    end
  end

  describe Datadog::Tracing::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to match(
          enabled: true,
          agent_url: start_with("http://#{agent_hostname}:#{agent_port}?timeout="),
          analytics_enabled: false,
          sample_rate: nil,
          sampling_rules: nil,
          integrations_loaded: nil,
          partial_flushing_enabled: false,
          priority_sampling_enabled: false,
        )
      end

      context 'with tracer disabled' do
        before { Datadog.configure { |c| c.tracing.enabled = false } }

        after { Datadog.configure { |c| c.tracing.enabled = true } }

        it { is_expected.to include enabled: false }
      end

      context 'with IO transport' do
        before do
          Datadog.configure do |c|
            c.tracing.writer = Datadog::Tracing::SyncWriter.new(
              transport: Datadog::Transport::IO.default
            )
          end
        end

        after { Datadog.configure { |c| c.tracing.writer = nil } }

        it { is_expected.to include agent_url: nil }
      end

      context 'with unix socket transport' do
        before do
          Datadog.configure do |c|
            c.tracing.transport_options = ->(t) { t.adapter :unix, '/tmp/trace.sock' }
          end
        end

        after { Datadog.configure { |c| c.tracing.transport_options = {} } }

        it { is_expected.to include agent_url: include('unix') }
        it { is_expected.to include agent_url: include('/tmp/trace.sock') }
      end

      context 'with analytics enabled' do
        before { Datadog.configure { |c| c.tracing.analytics.enabled = true } }

        it { is_expected.to include analytics_enabled: true }
      end

      # context 'with agent connectivity issues' do
      #   let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

      #   it { is_expected.to include agent_error: include('ZeroDivisionError') }
      #   it { is_expected.to include agent_error: include('msg') }
      # end

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
          before { Datadog.configure { |c| c.tracing.partial_flush.enabled = true } }
  
          it { is_expected.to include partial_flushing_enabled: true }
        end
  
        context 'with priority sampling enabled' do
          before { Datadog.configure { |c| c.tracing.priority_sampling = true } }
  
          it { is_expected.to include priority_sampling_enabled: true }
        end
      end
    end
  end
end
