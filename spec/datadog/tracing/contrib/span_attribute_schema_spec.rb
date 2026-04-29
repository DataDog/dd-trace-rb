require 'datadog/tracing/contrib/span_attribute_schema'

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema do
  describe '.default_or_global_service_name' do
    subject(:service_name) { described_class.default_or_global_service_name(default_service_name) }

    let(:default_service_name) { 'default-integration-service-name' }

    around do |example|
      without_warnings { Datadog.configuration.reset! }
      example.run
      without_warnings { Datadog.configuration.reset! }
    end

    context 'when global default service name is disabled' do
      it 'returns the integration default service name' do
        expect(service_name).to eq(default_service_name)
      end
    end

    context 'when global default service name is enabled' do
      before do
        Datadog.configure do |c|
          c.service = 'service'
          c.tracing.contrib.global_default_service_name.enabled = true
        end
      end

      it 'returns the configured global service name' do
        expect(service_name).to eq('service')
      end
    end
  end

  describe '#set_peer_service!' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
    subject(:set_peer_service!) { described_class.set_peer_service!(span, precursors) }

    with_env 'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED' => 'true'

    context 'precursor tags set' do
      context 'AWS Span' do
        let(:precursors) do
          ['statemachinename',
            'rulename',
            'bucketname',
            'tablename',
            'streamname',
            'topicname',
            'queuename']
        end
        it 'returns {AWS_PRECURSOR} as peer.service and source' do
          span.set_tag('aws_service', 'test-service')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end

        context 'peer service defaults disabled' do
          with_env 'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED' => 'false'

          it 'does not set peer.service' do
            span.set_tag('aws_service', 'test-service')
            span.set_tag('span.kind', 'client')
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              set_peer_service!
              expect(span.get_tag('peer.service')).to be_nil
              expect(span.get_tag('_dd.peer.service.source')).to be_nil
              expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end

      context 'DB Span' do
        let(:precursors) { ['db.instance'] }
        it 'returns {DB_PRECURSOR} as peer.service and source' do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'Messaging Span' do
        let(:precursors) { [] }
        it 'returns {MSG_PRECURSOR} as peer.service and source' do
          span.set_tag('messaging.system', 'test-msg-system')
          span.set_tag('span.kind', 'producer')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'RPC Span' do
        let(:precursors) { ['rpc.service'] }
        it 'returns {RPC_PRECURSOR} as peer.service and source' do
          span.set_tag('rpc.system', 'test-rpc')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'no precursor tags set' do
      let(:precursors) { ['out.host', 'peer.hostname', 'network.destination.name'] }
      context 'AWS Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('aws_service', 'test-service')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'DB Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'Messaging Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('messaging.system', 'test-msg-system')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'RPC Span' do
        it 'returns {PRECURSOR} as peer.service and source' do
          span.set_tag('rpc.system', 'test-rpc')
          span.set_tag('span.kind', 'client')
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.set_peer_service!(span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)
            expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end
    end

    context 'no peer.service value found' do
      let(:precursors) { ['precursor-tag'] }
      it 'returns false to show no source or value found' do
        span.set_tag('db.system', 'test-db')
        span.set_tag('span.kind', 'client')
        expect(described_class.set_peer_service!(span, precursors)).to be false
        expect(span.get_tag('peer.service')).to be_nil
        expect(span.get_tag('_dd.peer.service.source')).to be_nil
        expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil
      end
    end

    context 'peer.service already set' do
      let(:precursors) { ['precursor-tag'] }
      it 'returns true with peer.service already set' do
        span.set_tag('db.system', 'test-db')
        span.set_tag('span.kind', 'client')
        span.set_tag('peer.service', 'peer-service-value')
        expect(described_class.set_peer_service!(span, precursors)).to be true
        expect(span.get_tag('peer.service')).to eq('peer-service-value')
        expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        expect(span.get_tag('_dd.peer.service.remapped_from')).to be_nil
      end

      context 'remaps peer.service and source with peer.service already set' do
        with_env DD_TRACE_PEER_SERVICE_MAPPING: 'peer-service-value:test-remap'

        it do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          span.set_tag('peer.service', 'peer-service-value')

          expect(described_class.set_peer_service!(span, precursors)).to be true
          expect(span.get_tag('peer.service')).to eq('test-remap')
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
          expect(span.get_tag('_dd.peer.service.remapped_from')).to eq('peer-service-value')
        end
      end

      context 'peer service defaults disabled' do
        with_env 'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED' => 'false'

        it 'keeps explicit peer.service' do
          span.set_tag('peer.service', 'peer-service-value')

          set_peer_service!

          expect(span.get_tag('peer.service')).to eq('peer-service-value')
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
        end
      end
    end

    context 'remapping tags' do
      let(:precursor) { ['precursor-tag'] }

      context 'remaps peer.service and source' do
        with_env DD_TRACE_PEER_SERVICE_MAPPING: 'test-precursor:test-remap'

        it do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          span.set_tag('precursor-tag', 'test-precursor')

          expect(described_class.set_peer_service!(span, precursor)).to be true
          expect(span.get_tag('peer.service')).to eq('test-remap')
          expect(span.get_tag('_dd.peer.service.source')).to eq('precursor-tag')
          expect(span.get_tag('_dd.peer.service.remapped_from')).to eq('test-precursor')
        end
      end
    end
  end
end
