require 'spec_helper'

require 'datadog/tracing/transport/traces'

RSpec.describe Datadog::Tracing::Transport::Traces::EncodedParcel do
  subject(:parcel) { described_class.new(data, trace_count) }

  let(:data) { instance_double(Array) }
  let(:trace_count) { 123 }

  it { is_expected.to be_a_kind_of(Datadog::Core::Transport::Parcel) }

  describe '#initialize' do
    it { is_expected.to have_attributes(data: data) }
  end

  describe '#count' do
    subject(:count) { parcel.count }

    let(:length) { double('length') }

    before { expect(data).to receive(:length).and_return(length) }

    it { is_expected.to be length }
  end

  describe '#trace_count' do
    subject { parcel.trace_count }

    it { is_expected.to eq(trace_count) }
  end
end

RSpec.describe Datadog::Tracing::Transport::Traces::Request do
  subject(:request) { described_class.new(parcel) }

  let(:parcel) { double }

  it { is_expected.to be_a_kind_of(Datadog::Core::Transport::Request) }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(parcel: parcel)
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::Traces::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Tracing::Transport::Traces::Response })
    end

    describe '#service_rates' do
      it { is_expected.to respond_to(:service_rates) }
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::Traces::Chunker do
  let(:logger) { logger_allowing_debug }
  let(:chunker) do
    described_class.new(encoder, logger: logger, native_events_supported: native_events_supported, max_size: max_size)
  end
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }
  let(:native_events_supported) { double }
  let(:trace_encoder) { Datadog::Tracing::Transport::Traces::Encoder }
  let(:max_size) { 10 }

  describe '#encode_in_chunks' do
    subject(:encode_in_chunks) { chunker.encode_in_chunks(traces) }

    context 'with traces' do
      let(:traces) { get_test_traces(3) }

      before do
        allow(trace_encoder).to receive(:encode_trace).with(
          encoder,
          traces[0],
          logger: logger,
          native_events_supported: native_events_supported
        ).and_return('1')
        allow(trace_encoder).to receive(:encode_trace).with(
          encoder,
          traces[1],
          logger: logger,
          native_events_supported: native_events_supported
        ).and_return('22')
        allow(trace_encoder).to receive(:encode_trace).with(
          encoder,
          traces[2],
          logger: logger,
          native_events_supported: native_events_supported
        ).and_return('333')
        allow(encoder).to receive(:join) { |arr| arr.join(',') }
      end

      it do
        is_expected.to eq([['1,22,333', 3]])
      end

      context 'with batching required' do
        let(:max_size) { 3 }

        it do
          is_expected.to eq([['1,22', 2], ['333', 1]])
        end
      end

      context 'with individual traces too large' do
        include_context 'health metrics'

        let(:max_size) { 1 }

        before do
          Datadog.configuration.diagnostics.debug = true
          allow(Datadog.logger).to receive(:debug)
        end

        it 'drops all traces except the smallest' do
          is_expected.to eq([['1', 1]])
          expect(logger).to have_lazy_debug_logged(/Payload too large/)
          expect(health_metrics).to have_received(:transport_trace_too_large).with(1).twice
        end
      end
    end

    context 'with a lazy enumerator' do
      let(:traces) { [].lazy }

      before do
        if PlatformHelpers.jruby? && PlatformHelpers.engine_version < Gem::Version.new('9.2.9.0')
          skip 'This runtime returns eager enumerators on Enumerator::Lazy methods calls'
        end
      end

      it 'does not force enumerator expansion' do
        expect(encode_in_chunks).to be_a(Enumerator::Lazy)
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::Traces::Transport do
  let(:logger) { logger_allowing_debug }

  subject(:transport) { described_class.new(apis, current_api_id, logger: logger) }

  shared_context 'APIs with fallbacks' do
    let(:current_api_id) { :v2 }
    let(:apis) do
      Datadog::Core::Transport::HTTP::API::Map[
        v2: api_v2,
        v1: api_v1
      ].with_fallbacks(v2: :v1)
    end

    let(:api_v1) { instance_double(Datadog::Tracing::Transport::HTTP::Traces::API::Instance, 'v1', encoder: encoder_v1) }
    let(:api_v2) { instance_double(Datadog::Tracing::Transport::HTTP::Traces::API::Instance, 'v2', encoder: encoder_v2) }
    let(:encoder_v1) { instance_double(Datadog::Core::Encoding::Encoder, 'v1', content_type: 'text/plain') }
    let(:encoder_v2) { instance_double(Datadog::Core::Encoding::Encoder, 'v2', content_type: 'text/csv') }
  end

  describe '#initialize' do
    include_context 'APIs with fallbacks'

    it { expect(transport.stats).to be_a(Datadog::Tracing::Transport::Statistics::Counts) }

    it { is_expected.to have_attributes(apis: apis, current_api_id: current_api_id) }
  end

  describe '#send_traces' do
    include_context 'APIs with fallbacks'
    include_context 'health metrics'

    subject(:send_traces) { transport.send_traces(traces) }

    let(:traces) { [] }

    let(:response) { Class.new { include Datadog::Core::Transport::Response }.new }
    let(:responses) { [response] }

    let(:encoded_traces) { double }
    let(:trace_count) { 1 }
    let(:chunks) { [[encoded_traces, trace_count]] }
    let(:lazy_chunks) { chunks.lazy }

    let(:request) { instance_double(Datadog::Tracing::Transport::Traces::Request) }
    let(:client_v2) { instance_double(Datadog::Tracing::Transport::HTTP::Client) }
    let(:client_v1) { instance_double(Datadog::Tracing::Transport::HTTP::Client) }

    let(:chunker) { instance_double(Datadog::Tracing::Transport::Traces::Chunker, max_size: 1) }
    let(:native_events_supported) { nil }
    let(:agent_info_response) do
      instance_double(Datadog::Core::Remote::Transport::HTTP::Negotiation::Response, span_events: native_events_supported)
    end

    before do
      allow(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
        encoder_v1,
        logger: logger,
        native_events_supported: false
      ).and_return(chunker)
      allow(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
        encoder_v2,
        logger: logger,
        native_events_supported: false
      ).and_return(chunker)

      allow(chunker).to receive(:encode_in_chunks).and_return(lazy_chunks)

      allow(Datadog::Tracing::Transport::HTTP::Client).to receive(:new).with(api_v1, logger: logger).and_return(client_v1)
      allow(Datadog::Tracing::Transport::HTTP::Client).to receive(:new).with(api_v2, logger: logger).and_return(client_v2)
      allow(client_v1).to receive(:send_traces_payload).with(request).and_return(response)
      allow(client_v2).to receive(:send_traces_payload).with(request).and_return(response)

      allow(Datadog::Tracing::Transport::Traces::Request).to receive(:new).and_return(request)

      allow_any_instance_of(Datadog::Core::Environment::AgentInfo).to receive(:fetch)
        .and_return(agent_info_response)
    end

    context 'which returns an OK response' do
      before { allow(response).to receive(:ok?).and_return(true) }

      it 'sends to only the current API once' do
        is_expected.to eq(responses)
        expect(client_v2).to have_received(:send_traces_payload).with(request).once

        expect(health_metrics).to have_received(:transport_chunked).with(1)
      end

      context 'with a runtime that returns eagerly loaded chunks' do
        before do
          if !PlatformHelpers.jruby? || PlatformHelpers.engine_version >= Gem::Version.new('9.2.9.0')
            skip 'This runtime correctly returns lazy enumerators on Enumerator::Lazy#slice_before calls'
          end
        end

        let(:lazy_chunks) { chunks }

        it 'successfully sends a single request' do
          is_expected.to eq(responses)
          expect(client_v2).to have_received(:send_traces_payload).with(request).once

          expect(health_metrics).to have_received(:transport_chunked).with(1)
        end
      end

      context 'with many chunks' do
        let(:chunks) { [[], []] }
        let(:responses) { [response, response] }

        it do
          is_expected.to eq(responses)
          expect(health_metrics).to have_received(:transport_chunked).with(2)
        end
      end
    end

    context 'which returns a not found response' do
      before do
        allow(response).to receive(:not_found?).and_return(true)
        allow(response).to receive(:client_error?).and_return(true)
      end

      it 'attempts each API once as it falls back after each failure' do
        is_expected.to eq(responses)

        expect(client_v2).to have_received(:send_traces_payload).with(request).once
        expect(client_v1).to have_received(:send_traces_payload).with(request).once

        expect(health_metrics).to have_received(:transport_chunked).with(1)
      end
    end

    context 'which returns an unsupported response' do
      before do
        allow(response).to receive(:unsupported?).and_return(true)
        allow(response).to receive(:client_error?).and_return(true)
      end

      it 'attempts each API once as it falls back after each failure' do
        is_expected.to eq(responses)

        expect(client_v2).to have_received(:send_traces_payload).with(request).once
        expect(client_v1).to have_received(:send_traces_payload).with(request).once

        expect(health_metrics).to have_received(:transport_chunked).with(1)
      end
    end

    context 'for native span event support by the agent' do
      after do
        Datadog.configuration.tracing.reset_options!
      end
      context 'when native_span_events option is configured' do
        context 'when set to true' do
          before do
            Datadog.configuration.tracing.native_span_events = true
          end

          let(:native_events_supported) { true }

          it 'uses the configured value' do
            expect(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
              encoder_v2,
              logger: logger,
              native_events_supported: true
            ).and_return(chunker)

            send_traces
          end

          it 'does not query the agent' do
            allow(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).and_return(chunker)
            expect_any_instance_of(Datadog::Core::Environment::AgentInfo).not_to receive(:fetch)

            send_traces
          end
        end

        context 'when set to false' do
          before do
            Datadog.configuration.tracing.native_span_events = false
          end

          let(:native_events_supported) { false }

          it 'uses the configured value' do
            expect(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
              encoder_v2,
              logger: logger,
              native_events_supported: false
            ).and_return(chunker)
            send_traces
          end

          it 'does not query the agent' do
            allow(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).and_return(chunker)
            expect_any_instance_of(Datadog::Core::Environment::AgentInfo).not_to receive(:fetch)

            send_traces
          end
        end
      end

      context 'when native_span_events option is not configured' do
        context 'on a successful agent info call' do
          context 'with support not advertised' do
            let(:native_events_supported) { nil }

            it 'does not encode native span events' do
              expect(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
                encoder_v2,
                logger: logger,
                native_events_supported: false
              ).and_return(chunker)
              send_traces
            end
          end

          context 'with support advertised as supported' do
            let(:native_events_supported) { true }

            it 'encodes native span events' do
              expect(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
                encoder_v2,
                logger: logger,
                native_events_supported: true
              ).and_return(chunker)
              send_traces
            end
          end

          context 'with support advertised as unsupported' do
            let(:native_events_supported) { false }

            it 'encodes native span events' do
              expect(Datadog::Tracing::Transport::Traces::Chunker).to receive(:new).with(
                encoder_v2,
                logger: logger,
                native_events_supported: false
              ).and_return(chunker)
              send_traces
            end
          end

          it 'caches the agent result' do
            transport.send_traces(traces)
            transport.send_traces(traces)

            expect(Datadog.send(:components).agent_info).to have_received(:fetch).once
          end
        end

        context 'on an unsuccessful agent info call' do
          let(:agent_info_response) { nil }

          it 'does not cache the agent result' do
            transport.send_traces(traces)
            transport.send_traces(traces)

            expect(Datadog.send(:components).agent_info).to have_received(:fetch).twice
          end
        end
      end
    end
  end

  describe '#downgrade?' do
    include_context 'APIs with fallbacks'

    subject(:downgrade?) { transport.send(:downgrade?, response) }

    let(:response) { instance_double(Datadog::Core::Transport::Response) }

    context 'when there is no fallback' do
      let(:current_api_id) { :v1 }

      it { is_expected.to be false }
    end

    context 'when a fallback is available' do
      let(:current_api_id) { :v2 }

      context 'and the response isn\'t \'not found\' or \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be false }
      end

      context 'and the response is \'not found\'' do
        before do
          allow(response).to receive(:not_found?).and_return(true)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be true }
      end

      context 'and the response is \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(true)
        end

        it { is_expected.to be true }
      end
    end
  end

  describe '#current_api' do
    include_context 'APIs with fallbacks'

    subject(:current_api) { transport.current_api }

    it { is_expected.to be(api_v2) }
  end

  describe '#change_api!' do
    include_context 'APIs with fallbacks'

    subject(:change_api!) { transport.send(:change_api!, api_id) }

    context 'when the API ID does not match an API' do
      let(:api_id) { :v99 }

      it { expect { change_api! }.to raise_error(described_class::UnknownApiVersionError) }
    end

    context 'when the API ID matches an API' do
      let(:api_id) { :v1 }

      it { expect { change_api! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end

  describe '#downgrade!' do
    include_context 'APIs with fallbacks'

    subject(:downgrade!) { transport.send(:downgrade!) }

    context 'when the API has no fallback' do
      let(:current_api_id) { :v1 }

      it { expect { downgrade! }.to raise_error(described_class::NoDowngradeAvailableError) }
    end

    context 'when the API has fallback' do
      let(:current_api_id) { :v2 }

      it { expect { downgrade! }.to change { transport.current_api }.from(api_v2).to(api_v1) }
    end
  end
end
