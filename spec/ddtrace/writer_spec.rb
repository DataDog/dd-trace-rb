require 'spec_helper'

require 'ddtrace'
require 'json'

RSpec.describe Datadog::Writer do
  include HttpHelpers

  include_context 'metrics'

  before(:each) { WebMock.enable! }
  after(:each) do
    WebMock.reset!
    WebMock.disable!
  end

  describe 'instance' do
    subject(:writer) { described_class.new(options).tap { |w| w.statsd = statsd } }
    let(:options) { {} }

    describe 'behavior' do
      describe '#initialize' do
        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::PrioritySampler) }

          context 'and default transport options' do
            it do
              sampling_method = described_class.new.method(:sampling_updater)
              expect(Datadog::HTTPTransport).to receive(:new) do |hostname, port, options|
                expect(hostname).to eq(described_class::HOSTNAME)
                expect(port).to eq(described_class::PORT)
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
              expect(Datadog::HTTPTransport).to receive(:new) do |hostname, port, options|
                expect(hostname).to eq(described_class::HOSTNAME)
                expect(port).to eq(described_class::PORT)
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
        subject(:result) { writer.send_spans(traces, writer.transport) }
        let(:traces) { get_test_traces(1) }

        let!(:request) { stub_request(:post, endpoint).to_return(response) }
        let(:endpoint) { "#{Datadog::Writer::HOSTNAME}:#{Datadog::Writer::PORT}/#{api_version}/traces" }
        let(:response) { { body: body } }
        let(:body) { 'body' }
        let(:api_version) { Datadog::HTTPTransport::V3 }

        it_behaves_like 'an operation that sends time metric',
                        Datadog::Writer::METRIC_FLUSH_TIME,
                        tags: [Datadog::Ext::Metrics::TAG_DATA_TYPE_TRACES]

        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::Sampler) }

          context 'when the transport uses' do
            let(:options) { super().merge!(transport_options: { api_version: api_version, response_callback: callback }) }
            let(:callback) { double('callback method') }

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
                  "#{Datadog::Writer::HOSTNAME}:#{Datadog::Writer::PORT}/#{fallback_version}/traces"
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
      end

      describe '#send_services' do
        subject(:result) { writer.send_services(services, writer.transport) }
        let(:services) { get_test_services }

        let!(:request) { stub_request(:post, endpoint).to_return(response) }
        let(:endpoint) { "#{Datadog::Writer::HOSTNAME}:#{Datadog::Writer::PORT}/#{api_version}/services" }
        let(:response) { { body: body } }
        let(:body) { 'body' }
        let(:api_version) { Datadog::HTTPTransport::V3 }

        it_behaves_like 'an operation that sends time metric',
                        Datadog::Writer::METRIC_FLUSH_TIME,
                        tags: [Datadog::Ext::Metrics::TAG_DATA_TYPE_SERVICES]
      end

      describe '#sampling_updater' do
        subject(:result) { writer.send(:sampling_updater, action, response, api) }
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

                before(:each) { expect(sampler).to receive(:update).with(service_rates) }

                it { is_expected.to be true }
                it_behaves_like 'an operation that sends time metric',
                                Datadog::Writer::METRIC_SAMPLING_UPDATE_TIME,
                                tags: [Datadog::Ext::Metrics::TAG_PRIORITY_SAMPLING_ENABLED]
              end

              context 'and is API v3' do
                let(:api) { { version: Datadog::HTTPTransport::V3 } }
                let(:body) { 'OK' }

                before(:each) { expect(sampler).to_not receive(:update) }

                it { is_expected.to be false }
                it_behaves_like 'an operation that sends time metric',
                                Datadog::Writer::METRIC_SAMPLING_UPDATE_TIME,
                                tags: [Datadog::Ext::Metrics::TAG_PRIORITY_SAMPLING_ENABLED]
              end
            end
          end
        end
      end
    end
  end
end
