require 'datadog/tracing/contrib/span_attribute_schema'

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema do
  describe '#fetch_service_name' do
    context 'when integration service is set' do
      it 'returns the integration specific service name' do
        with_modified_env DD_INTEGRATION_SERVICE: 'integration-service-name' do
          expect(
            described_class
              .fetch_service_name('DD_INTEGRATION_SERVICE',
                'default-integration-service-name')
          ).to eq('integration-service-name')
        end
      end
    end

    context 'when DD_SERVICE is set' do
      it 'returns default integration service name' do
        with_modified_env DD_SERVICE: 'service' do
          expect(
            described_class
              .fetch_service_name('DD_INTEGRATION_SERVICE',
                'default-integration-service-name')
          ).to eq('default-integration-service-name')
        end
      end
    end

    context 'when DD_SERVICE is not set' do
      it 'returns default integration service name' do
        expect(
          described_class
            .fetch_service_name('DD_INTEGRATION_SERVICE',
              'default-integration-service-name')
        ).to eq('default-integration-service-name')
      end
    end

    context 'when DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED is set' do
      it 'returns DD_SERVICE' do
        with_modified_env DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true',
          DD_SERVICE: 'service' do
            expect(
              described_class
                .fetch_service_name('DD_INTEGRATION_SERVICE',
                  'default-integration-service-name')
            ).to eq('service')
          end
      end
    end
  end

  describe '#set_peer_service!' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
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

      it 'remaps peer.service and source with peer.service already set' do
        span.set_tag('db.system', 'test-db')
        span.set_tag('span.kind', 'client')
        span.set_tag('peer.service', 'peer-service-value')

        with_modified_env DD_TRACE_PEER_SERVICE_MAPPING: 'peer-service-value:test-remap' do
          expect(described_class.set_peer_service!(span, precursors)).to be true
          expect(span.get_tag('peer.service')).to eq('test-remap')
          expect(span.get_tag('_dd.peer.service.source')).to eq('peer.service')
          expect(span.get_tag('_dd.peer.service.remapped_from')).to eq('peer-service-value')
        end
      end
    end

    context 'remapping tags' do
      let(:precursor) { ['precursor-tag'] }

      it 'remaps peer.service and source' do
        span.set_tag('db.system', 'test-db')
        span.set_tag('span.kind', 'client')
        span.set_tag('precursor-tag', 'test-precursor')

        with_modified_env DD_TRACE_PEER_SERVICE_MAPPING: 'test-precursor:test-remap' do
          expect(described_class.set_peer_service!(span, precursor)).to be true
          expect(span.get_tag('peer.service')).to eq('test-remap')
          expect(span.get_tag('_dd.peer.service.source')).to eq('precursor-tag')
          expect(span.get_tag('_dd.peer.service.remapped_from')).to eq('test-precursor')
        end
      end
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
