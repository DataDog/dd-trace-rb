require 'spec_helper'

require 'datadog/core/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Tracing::Diagnostics::TracingEnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to include(
          enabled: true,
          agent_url: start_with("http://#{agent_hostname}:#{agent_port}?timeout="),
          analytics_enabled: false,
          sample_rate: nil,
          sampling_rules: nil,
          partial_flushing_enabled: false,
          priority_sampling_enabled: false,
        )
      end

      context 'with tracer disabled' do
        before { Datadog.configure { |c| c.tracing.enabled = false } }

        after { Datadog.configure { |c| c.tracing.enabled = true } }

        it { is_expected.to include enabled: false }
      end

      context 'with analytics enabled' do
        before { Datadog.configure { |c| c.tracing.analytics.enabled = true } }

        it { is_expected.to include analytics_enabled: true }
      end

      context 'with partial flushing enabled' do
        before { Datadog.configure { |c| c.tracing.partial_flush.enabled = true } }

        it { is_expected.to include partial_flushing_enabled: true }
      end

      context 'with priority sampling enabled' do
        before { Datadog.configure { |c| c.tracing.priority_sampling = true } }

        it { is_expected.to include priority_sampling_enabled: true }
      end

      context 'with agent connectivity issues' do
        let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

        it { is_expected.to include agent_error: include('ZeroDivisionError') }
        it { is_expected.to include agent_error: include('msg') }
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
      end
    end

    describe '#collect_errors!' do
      subject(:collect_errors!) { collector.collect_errors!([response]) } # is this line necessary?

      let(:collector) { described_class.new } # is this line necessary?
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) } # is this line necessary?

      it 'with a default tracer' do
        is_expected.to include agent_error: nil
      end

      context 'with agent connectivity issues' do
        let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

        it { is_expected.to include agent_error: include('ZeroDivisionError') }
        it { is_expected.to include agent_error: include('msg') }
      end
    end
  end
end
