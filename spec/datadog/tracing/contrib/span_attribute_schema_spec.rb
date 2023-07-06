require 'datadog/tracing/contrib/span_attribute_schema'

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema do
  describe '#default_span_attribute_schema?' do
    context 'when default schema is set' do
      it 'returns true' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.default_span_attribute_schema?).to eq(true)
        end
      end
    end

    context 'when default schema is changed' do
      it 'returns false' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.default_span_attribute_schema?).to eq(false)
        end
      end
    end

    context 'when default schema is not set' do
      it 'returns true' do
        expect(described_class.default_span_attribute_schema?).to eq(true)
      end
    end
  end

  describe '#active_version' do
    context 'when v0 set' do
      it 'equals v0' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(described_class.send(:active_version)).to eq(described_class::V0)
        end
      end
    end

    context 'when v1 is set' do
      it 'equals v1' do
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1' do
          expect(described_class.send(:active_version)).to eq(described_class::V1)
        end
      end
    end

    context 'when no schema is set' do
      it 'equals v0' do
        expect(described_class.send(:active_version)).to eq(described_class::V0)
      end
    end
  end

  describe '#fetch_service_name' do
    subject(:fetch_service_name) { described_class.fetch_service_name(env, default) }
    let(:env) { instance_double(String) }
    let(:default) { instance_double(String) }
    let(:active_version) { double('active_version') }
    let(:return_value) { instance_double(String) }

    before do
      allow(described_class).to receive(:active_version).and_return(active_version)
      expect(active_version).to receive(:fetch_service_name).with(env, default).and_return(return_value)
    end

    it do
      is_expected.to eq(return_value)
    end
  end

  describe '#set_peer_service!' do
    subject(:set_peer_service!) { described_class.set_peer_service!(span, sources) }
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:sources) { instance_double(Array) }
    let(:active_version) { double('active_version') }
    let(:return_value) { double('return_value') }

    before do
      allow(described_class).to receive(:active_version).and_return(active_version)
      expect(active_version).to receive(:set_peer_service!).with(span, sources).and_return(return_value)
    end

    it do
      is_expected.to eq(return_value)
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema::V0 do
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
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0', DD_SERVICE: 'service' do
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
        with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0' do
          expect(
            described_class
              .fetch_service_name('DD_INTEGRATION_SERVICE',
                'default-integration-service-name')
          ).to eq('default-integration-service-name')
        end
      end
    end
  end

  describe '#set_peer_service!' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
    it 'returns {span.service} and peer.service as source' do
      span.service = 'test-peer.service'
      expect(described_class.send(:set_peer_service!, span, [])).to be false
      expect(span.get_tag('peer.service')).to eq('test-peer.service')
      expect(span.get_tag('_dd.peer.service.source')).to eq nil
    end
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end

RSpec.describe Datadog::Tracing::Contrib::SpanAttributeSchema::V1 do
  describe '#fetch_service_name' do
    context 'for v1' do
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

        context 'when DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED is set' do
          it 'returns DD_SERVICE' do
            with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v1',
              DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true',
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

      context 'when DD_SERVICE is set' do
        it 'returns default integration service name' do
          with_modified_env DD_SERVICE: 'service' do
            expect(
              described_class
                .fetch_service_name('DD_INTEGRATION_SERVICE',
                  'default-integration-service-name')
            ).to eq('service')
          end
        end
      end

      context 'when DD_SERVICE is not set' do
        it 'returns default integration service name' do
          expect(
            described_class
              .fetch_service_name('DD_INTEGRATION_SERVICE',
                'default-integration-service-name')
          ).to eq('rspec')
        end
      end
    end
  end

  describe '#set_peer_service!' do
    let(:span) { Datadog::Tracing::Span.new('testPeerServiceLogicSpan', parent_id: 0) }
    context 'for v1' do
      context 'AWS Span' do
        it 'returns {AWS_PRECURSOR} as peer.service and source' do
          span.set_tag('aws_service', 'test-service')
          span.set_tag('span.kind', 'client')
          precursors = Array['statemachinename',
            'rulename',
            'bucketname',
            'tablename',
            'streamname',
            'topicname',
            'queuename']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service!, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'DB Span' do
        it 'returns {DB_PRECURSOR} as peer.service and source' do
          span.set_tag('db.system', 'test-db')
          span.set_tag('span.kind', 'client')
          precursors = Array['db.instance']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service!, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'Messaging Span' do
        it 'returns {MSG_PRECURSOR} as peer.service and source' do
          span.set_tag('messaging.system', 'test-msg-system')
          span.set_tag('span.kind', 'producer')
          precursors = Array[]
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service!, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'RPC Span' do
        it 'returns {RPC_PRECURSOR} as peer.service and source' do
          span.set_tag('rpc.system', 'test-rpc')
          span.set_tag('span.kind', 'client')
          precursors = Array['rpc.service']
          precursors.each do |precursor|
            span.set_tag(precursor, 'test-' << precursor)

            expect(described_class.send(:set_peer_service!, span, precursors)).to be true
            expect(span.get_tag('peer.service')).to eq('test-' << precursor)
            expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

            span.clear_tag('peer.service')
            span.clear_tag('_dd.peer.service.source')
            span.clear_tag(precursor)
          end
        end
      end

      context 'no precursor tags set' do
        context 'AWS Span' do
          it 'returns {PRECURSOR} as peer.service and source' do
            span.set_tag('aws_service', 'test-service')
            span.set_tag('span.kind', 'client')
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

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
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

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
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

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
            precursors = Array['out.host', 'peer.hostname', 'network.destination.name']
            precursors.each do |precursor|
              span.set_tag(precursor, 'test-' << precursor)

              expect(described_class.send(:set_peer_service!, span, precursors)).to be true
              expect(span.get_tag('peer.service')).to eq('test-' << precursor)
              expect(span.get_tag('_dd.peer.service.source')).to eq(precursor)

              span.clear_tag('peer.service')
              span.clear_tag('_dd.peer.service.source')
              span.clear_tag(precursor)
            end
          end
        end
      end

      context 'when v0 schema is set AND DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED is set' do
        it 'returns DD_SERVICE' do
          with_modified_env DD_TRACE_SPAN_ATTRIBUTE_SCHEMA: 'v0',
            DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED: 'true',
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
  end

  def with_modified_env(options = {}, &block)
    ClimateControl.modify(options, &block)
  end
end
