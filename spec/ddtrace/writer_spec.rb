require 'spec_helper'

require 'ddtrace'
require 'json'

RSpec.describe Datadog::Writer do
  include HttpHelpers

  before(:each) { WebMock.enable! }
  after(:each) do
    WebMock.reset!
    WebMock.disable!
  end

  describe 'instance' do
    subject(:writer) { described_class.new(options) }
    let(:options) { {} }

    describe 'behavior' do
      describe '#initialize' do
        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::PrioritySampler) }

          context 'and default transport options' do
            it do
              sampling_method = described_class.instance_method(:old_sampling_updater)
              expect(Datadog::HTTPTransport).to receive(:new) do |options|
                expect(options).to be_a_kind_of(Hash)
                expect(options[:api_version]).to eq(Datadog::HTTPTransport::V4)
                expect(options[:response_callback].source_location).to eq(sampling_method.source_location)
              end
              expect(writer.instance_variable_get(:@priority_sampler)).to be(sampler)
            end
          end

          context 'and custom transport options' do
            let(:options) { super().merge!(transport_options: transport_options) }
            let(:transport_options) { { api_version: api_version, response_callback: response_callback } }
            let(:api_version) { double('API version') }
            let(:response_callback) { double('response callback') }

            it do
              expect(Datadog::HTTPTransport).to receive(:new) do |options|
                expect(options).to include(
                  api_version: api_version,
                  response_callback: response_callback
                )
              end
              expect(writer.priority_sampler).to be(sampler)
            end
          end
        end
      end

      describe '#send_spans' do
        subject(:send_spans) { writer.send_spans(traces, writer.transport) }
        let(:traces) { get_test_traces(1) }

        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::Sampler) }

          context 'when the transport uses' do
            let(:options) { super().merge!(transport_options: { api_version: api_version, response_callback: callback }) }
            let(:callback) { double('callback method') }

            let!(:request) { stub_request(:post, endpoint).to_return(response) }
            let(:hostname) { ENV.fetch('DD_AGENT_HOST', Datadog::HTTPTransport::DEFAULT_AGENT_HOST) }
            let(:port) { ENV.fetch('DD_TRACE_AGENT_PORT', Datadog::HTTPTransport::DEFAULT_TRACE_AGENT_PORT) }
            let(:endpoint) { "#{hostname}:#{port}/#{api_version}/traces" }
            let(:response) { { body: body } }
            let(:body) { 'body' }

            shared_examples_for 'a traces API' do
              context 'that succeeds' do
                before(:each) do
                  expect(callback).to receive(:call).with(
                    :traces,
                    a_kind_of(Net::HTTPOK),
                    a_kind_of(Hash)
                  ) do |_action, _response, api|
                    expect(api[:version]).to eq(api_version)
                  end
                end

                it do
                  is_expected.to be true
                  assert_requested(request)
                end
              end

              context 'but falls back to v3' do
                let(:response) { super().merge!(status: 404) }
                let!(:fallback_request) { stub_request(:post, fallback_endpoint).to_return(body: body) }
                let(:fallback_endpoint) do
                  "#{hostname}:#{port}/#{fallback_version}/traces"
                end
                let(:body) { 'body' }

                before(:each) do
                  call_count = 0
                  allow(callback).to receive(:call).with(
                    :traces,
                    a_kind_of(Net::HTTPResponse),
                    a_kind_of(Hash)
                  ) do |_action, response, api|
                    call_count += 1
                    if call_count == 1
                      expect(response).to be_a_kind_of(Net::HTTPNotFound)
                      expect(api[:version]).to eq(api_version)
                    elsif call_count == 2
                      expect(response).to be_a_kind_of(Net::HTTPOK)
                      expect(api[:version]).to eq(fallback_version)
                    end
                  end
                end

                it do
                  is_expected.to be true
                  assert_requested(request)
                end
              end
            end

            context 'API v4' do
              it_behaves_like 'a traces API' do
                let(:api_version) { Datadog::HTTPTransport::V4 }
                let(:fallback_version) { Datadog::HTTPTransport::V3 }
              end
            end

            context 'API v3' do
              it_behaves_like 'a traces API' do
                let(:api_version) { Datadog::HTTPTransport::V3 }
                let(:fallback_version) { Datadog::HTTPTransport::V2 }
              end
            end
          end
        end

        context 'with report hostname' do
          let(:hostname) { 'my-host' }

          before(:each) do
            allow(Datadog::Runtime::Socket).to receive(:hostname).and_return(hostname)
          end

          context 'enabled' do
            around do |example|
              Datadog.configuration.report_hostname = Datadog.configuration.report_hostname.tap do
                Datadog.configuration.report_hostname = true
                example.run
              end
            end

            it do
              expect(writer.transport).to receive(:send) do |_type, traces|
                root_span = traces.first.first
                expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to eq(hostname)

                # Stub successful request
                200
              end

              send_spans
            end
          end

          context 'disabled' do
            around do |example|
              Datadog.configuration.report_hostname = Datadog.configuration.report_hostname.tap do
                Datadog.configuration.report_hostname = false
                example.run
              end
            end

            it do
              expect(writer.transport).to receive(:send) do |_type, traces|
                root_span = traces.first.first
                expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to be nil

                # Stub successful request
                200
              end

              send_spans
            end
          end
        end
      end

      describe '#send_runtime_metrics' do
        subject(:send_runtime_metrics) { writer.send_runtime_metrics }

        context 'when runtime metrics are' do
          context 'enabled' do
            around do |example|
              Datadog.configuration.runtime_metrics_enabled = Datadog.configuration.runtime_metrics_enabled.tap do
                Datadog.configuration.runtime_metrics_enabled = true
                example.run
              end
            end

            it do
              expect(writer.runtime_metrics).to receive(:flush)
              send_runtime_metrics
            end
          end

          context 'disabled' do
            around do |example|
              Datadog.configuration.runtime_metrics_enabled = Datadog.configuration.runtime_metrics_enabled.tap do
                Datadog.configuration.runtime_metrics_enabled = false
                example.run
              end
            end

            it do
              expect(writer.runtime_metrics).to_not receive(:flush)
              send_runtime_metrics
            end
          end
        end
      end

      describe '#old_sampling_updater' do
        subject(:result) { writer.send(:old_sampling_updater, action, response, api) }
        let(:options) { { priority_sampler: sampler } }
        let(:sampler) { instance_double(Datadog::PrioritySampler) }
        let(:action) { :traces }
        let(:response) { double('response') }
        let(:api) { double('api') }

        context 'given a response that' do
          context 'isn\'t OK' do
            let(:response) { mock_http_request(method: :post, status: 404)[:response] }
            it { is_expected.to be nil }
          end

          context 'isn\'t a :traces action' do
            let(:action) { :services }
            it { is_expected.to be nil }
          end

          context 'is OK' do
            let(:response) { mock_http_request(method: :post, body: body)[:response] }

            context 'and is a :traces action' do
              context 'and is API v4' do
                let(:api) { { version: Datadog::HTTPTransport::V4 } }
                let(:body) { sampling_response.to_json }
                let(:sampling_response) { { 'rate_by_service' => service_rates } }
                let(:service_rates) { { 'service:a,env:test' => 0.1, 'service:b,env:test' => 0.5 } }

                it do
                  expect(sampler).to receive(:update).with(service_rates)
                  is_expected.to be true
                end
              end

              context 'and is API v3' do
                let(:api) { { version: Datadog::HTTPTransport::V3 } }
                let(:body) { 'OK' }

                it do
                  expect(sampler).to_not receive(:update)
                  is_expected.to be false
                end
              end
            end
          end
        end
      end
    end
  end
end
