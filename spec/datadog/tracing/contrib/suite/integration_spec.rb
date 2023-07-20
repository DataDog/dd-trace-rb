require 'datadog/tracing/contrib/support/spec_helper'

require 'ddtrace'

# For testing dynamic configuration
require 'semantic_logger'
require 'rack'
require 'webrick'
require 'rackup'

RSpec.describe 'contrib integration testing' do
  describe 'dynamic configuration' do
    subject(:update_config) do
      stub_rc!

      @reconfigured = false
      allow(Datadog::Tracing::Remote).to receive(:process_config).and_wrap_original do |m, *args|
        m.call(*args).tap { @reconfigured = true }
      end
      try_wait_until { @reconfigured }
    end

    let(:stub_rc!) { stub_dynamic_configuration_request(dynamic_configuration) }

    before do
      WebMock.enable!

      stub_request(:get, %r{/info}).to_return(body: info_response, status: 200)
      stub_request(:post, %r{/v0\.7/config}).to_return(body: '{}', status: 200)

      Datadog.configure { |c| c.remote.poll_interval_seconds = 0.001 }
    end

    let(:info_response) { { endpoints: ['/v0.7/config'] }.to_json }
    let(:product) { 'APM_TRACING' }

    def new_dynamic_configuration(product = 'TEST-PRODUCT', data = '', config = 'test-config', name = 'test-name')
      Struct.new(:product, :data, :config, :name).new(product, data, config, name)
    end

    def stub_dynamic_configuration_request(*dynamic_configurations)
      stub_request(:post, %r{/v0\.7/config}).to_return(body: build(*dynamic_configurations), status: 200)
    end

    def build(*dynamic_configurations)
      target_files = []
      client_configs = []
      targets_targets = {}
      targets = {
        'signed' => {
          'custom' => {},
          'targets' => targets_targets,
        }
      }

      dynamic_configurations.each do |configuration|
        target = "datadog/1/#{configuration.product}/#{configuration.config}/#{configuration.name}"
        raw = configuration.data.to_json

        target_files << {
          'path' => target,
          'raw' => Base64.strict_encode64(raw),
        }

        targets_targets[target] = {
          'custom' => { 'v' => 1 },
          'length' => 0,
          'hashes' => { 'sha256' => Digest::SHA256.hexdigest(raw) },
        }
        client_configs << target
      end

      {
        'target_files' => target_files,
        'targets' => Base64.strict_encode64(targets.to_json),
        'client_configs' => client_configs,
      }.to_json
    end

    context 'with dynamic configuration data' do
      let(:dynamic_configuration) { new_dynamic_configuration(product, data) }
      let(:data) { { 'lib_config' => lib_config } }
      let(:lib_config) do
        {
          'log_injection_enabled' => false,
          'tracing_sampling_rate' => tracing_sampling_rate,
          'tracing_header_tags' => tracing_header_tags,
        }
      end

      let(:tracing_sampling_rate) { 0.7 }
      let(:tracing_header_tags) { [{ 'header' => 'test-header', 'tag_name' => '' }] }

      it 'overrides the local values' do
        expect(Datadog.configuration.tracing.sampling.default_rate).to be_nil
        expect(Datadog.configuration.tracing.log_injection).to eq(true)
        expect(Datadog.configuration.tracing.header_tags.to_s).to be_empty

        update_config

        wait_for { Datadog.configuration.tracing.sampling.default_rate }.to eq(0.7)
        wait_for { Datadog.configuration.tracing.log_injection }.to eq(false)
        wait_for { Datadog.configuration.tracing.header_tags.to_s }.to eq('test-header:')
      end

      context 'when remote configuration is later removed' do
        let(:empty_configuration) { stub_dynamic_configuration_request(empty_dynamic_configuration) }
        let(:empty_dynamic_configuration) { new_dynamic_configuration(product, empty_data) }
        let(:empty_data) { { 'lib_config' => {} } }

        it 'restore the local values' do
          update_config

          wait_for { Datadog.configuration.tracing.sampling.default_rate }.to eq(0.7)
          wait_for { Datadog.configuration.tracing.log_injection }.to eq(false)
          wait_for { Datadog.configuration.tracing.header_tags.to_s }.to eq('test-header:')

          empty_configuration

          wait_for { Datadog.configuration.tracing.sampling.default_rate }.to be_nil
          wait_for { Datadog.configuration.tracing.log_injection }.to eq(true)
          wait_for { Datadog.configuration.tracing.header_tags.to_s }.to be_empty
        end
      end

      context 'for tracing_header_tags' do
        let(:tracing_header_tags) { [{ 'header' => 'test-header', 'tag_name' => '' }] }

        before do
          Datadog.configure do |c|
            c.tracing.instrument :http
          end
        end

        let(:port) { @port }

        let!(:rack) do
          started = false
          server = WEBrick::HTTPServer.new(Port: 0, StartCallback: -> { started = true }, Logger: WEBrick::Log.new(StringIO.new))

          # Find resolved local port
          @port = server.config[:Port]

          app = Rack::Builder.new do
            use Datadog::Tracing::Contrib::Rack::TraceMiddleware
            map '/' do
              run ->(_env) { [200, { 'test-header' => 'test-response' }, ['Page Not Found!']] }
            end
          end.to_app

          server.mount '/', Rack::Handler::WEBrick, app

          Thread.new { server.start }
          try_wait_until { started }

          server
        end

        after { rack.shutdown }

        it 'changes the HTTP header tagging for span' do
          # Before
          Net::HTTP.get(URI("http://localhost:#{port}/"), { 'test-header' => 'test-request' })

          expect(spans).to have(2).items
          http, rack = spans

          expect(http.get_tag('http.request.headers.test-header')).to be_nil
          expect(rack.get_tag('http.response.headers.test-header')).to  be_nil

          clear_traces!

          # After
          update_config

          Net::HTTP.get(URI("http://localhost:#{port}/"), { 'test-header' => 'test-request' })

          expect(spans).to have(2).items
          http, rack = spans

          expect(http.get_tag('http.request.headers.test-header')).to eq('test-request')
          expect(rack.get_tag('http.response.headers.test-header')).to eq('test-response')
        end
      end

      context 'for tracing_sampling_rate' do
        let(:tracing_sampling_rate) { 0.0 }

        it 'changes default sampling rate and sampling decision' do
          # Before
          tracer.trace('test') {}

          expect(trace.rule_sample_rate).to be_nil
          expect(trace.sampling_priority).to eq(1)

          clear_traces!

          # After
          update_config

          tracer.trace('test') {}

          expect(trace.rule_sample_rate).to eq(0.0)
          expect(trace.sampling_priority).to eq(-1)
        end
      end

      context 'for log_injection_enabled' do
        let(:tracing_sampling_rate) { 0.0 }

        before do
          Datadog.configure do |c|
            c.tracing.instrument :semantic_logger
          end
        end

        let(:io) { StringIO.new }

        let(:logger) do
          SemanticLogger.add_appender(io: io)
          SemanticLogger['TestClass']
        end

        after { SemanticLogger.clear_appenders! }

        it 'changes disables log injection' do
          # Before
          expect(Datadog.configuration.tracing.log_injection).to eq(true)

          tracer.trace('test') { logger.error('test-log') }

          expect(io.string).to include('trace_id')

          io.truncate(0)

          # After
          update_config

          expect(Datadog.configuration.tracing.log_injection).to eq(false)

          tracer.trace('test') { logger.error('test-log') }

          expect(io.string).to_not include('trace_id')
        end
      end
    end
  end
end

