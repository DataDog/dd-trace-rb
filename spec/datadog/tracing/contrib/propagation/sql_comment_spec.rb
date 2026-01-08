require 'datadog/tracing/contrib/propagation/sql_comment'
require 'datadog/tracing/contrib/propagation/sql_comment/mode'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment do
  let(:propagation_mode) { Datadog::Tracing::Contrib::Propagation::SqlComment::Mode.new(mode, append) }
  let(:append) { false }
  let(:agent_info) { instance_double(Datadog::Core::Environment::AgentInfo, propagation_hash: nil) }

  before do
    allow(Datadog).to receive(:send).with(:components).and_return(double(agent_info: agent_info))
  end

  describe '.annotate!' do
    let(:span_op) { Datadog::Tracing::SpanOperation.new('sql_comment_propagation_span', service: 'db_service') }

    context 'when `disabled` mode' do
      let(:mode) { 'disabled' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to be_nil
      end
    end

    context 'when `service` mode' do
      let(:mode) { 'service' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to be_nil
      end
    end

    context 'when `full` mode' do
      let(:mode) { 'full' }

      it do
        described_class.annotate!(span_op, propagation_mode)

        expect(span_op.get_tag('_dd.dbm_trace_injected')).to eq('true')
      end
    end

    context 'when the base hash is present' do
      let(:mode) { 'service' }

      before do
        allow(Datadog.send(:components)).to receive(:agent_info).and_return(agent_info)
        allow(agent_info).to receive(:propagation_hash).and_return(1234567890)
      end

      it 'sets the propagated hash on the span metric' do
        described_class.annotate!(span_op, propagation_mode)
        expect(span_op.get_metric('_dd.propagated_hash')).to eq(1234567890)
      end
    end

    context 'when the base hash is not present' do
      let(:mode) { 'service' }

      before do
        allow(agent_info).to receive(:propagation_hash).and_return(nil)
      end

      it 'does not set the propagated hash on the span metric' do
        described_class.annotate!(span_op, propagation_mode)
        expect(span_op.get_metric('_dd.propagated_hash')).to be_nil
      end
    end
  end

  describe '.prepend_comment' do
    around do |example|
      without_warnings { Datadog.configuration.reset! }
      example.run
      without_warnings { Datadog.configuration.reset! }
    end

    let(:sql_statement) { 'SELECT 1' }
    let(:append) { false }

    context 'when tracing is enabled' do
      before do
        Datadog.configure do |c|
          c.env = 'dev'
          c.service = 'api'
          c.version = '1.2'
        end
      end

      let(:span_op) do
        Datadog::Tracing::SpanOperation.new(
          'sample_span',
          service: 'db_service'
        )
      end
      let(:trace_op) do
        double(
          to_digest: Datadog::Tracing::TraceDigest.new(
            trace_id: 0xC0FFEE,
            span_id: 0xBEE,
            trace_flags: 0xFE
          )
        )
      end

      subject { described_class.prepend_comment(sql_statement, span_op, trace_op, propagation_mode) }

      context 'when `disabled` mode' do
        let(:mode) { 'disabled' }

        it { is_expected.to eq(sql_statement) }
      end

      context 'when `service` mode' do
        let(:mode) { 'service' }

        it do
          is_expected.to eq(
            "/*dde='dev',ddps='api',ddpv='1.2',dddbs='db_service'*/ #{sql_statement}"
          )
        end

        context 'when given a span operation tagged with peer.service' do
          let(:span_op) do
            Datadog::Tracing::SpanOperation.new(
              'sample_span',
              service: 'db_service',
              tags: {'peer.service' => 'db_peer_service'}
            )
          end

          it do
            is_expected.to eq(
              "/*dde='dev',ddps='api',ddpv='1.2',ddprs='db_peer_service',dddbs='db_peer_service'*/ #{sql_statement}"
            )
          end

          context 'when the base hash is present' do
            before do
              allow(agent_info).to receive(:propagation_hash).and_return(1234567890)
            end

            it 'includes the base hash in the comment' do
              is_expected.to include("ddsh='1234567890'")
            end
          end

          context 'when the base hash is not present' do
            before do
              allow(agent_info).to receive(:propagation_hash).and_return(nil)
            end

            it 'does not have the base hash in the comment' do
              is_expected.not_to include('ddsh')
            end
          end

          context 'matching the global service' do
            let(:span_op) do
              Datadog::Tracing::SpanOperation.new(
                'sample_span',
                service: 'db_service',
                tags: {'peer.service' => 'api'}
              )
            end

            it 'omits the redundant dddbs' do
              is_expected.to eq(
                "/*dde='dev',ddps='api',ddpv='1.2',ddprs='api'*/ #{sql_statement}"
              )
            end
          end
        end

        context 'when given a span operation tagged with db.instance' do
          let(:span_op) do
            Datadog::Tracing::SpanOperation.new(
              'sample_span',
              service: 'db_service',
              tags: {'db.instance' => 'db_name'}
            )
          end

          it do
            is_expected.to eq(
              "/*dde='dev',ddps='api',ddpv='1.2',dddb='db_name',dddbs='db_service'*/ #{sql_statement}"
            )
          end
        end

        context 'when given a span operation tagged with peer.hostname' do
          let(:span_op) do
            Datadog::Tracing::SpanOperation.new(
              'sample_span',
              service: 'db_service',
              tags: {'peer.hostname' => 'db_host'}
            )
          end

          it do
            is_expected.to eq(
              "/*dde='dev',ddps='api',ddpv='1.2',ddh='db_host',dddbs='db_service'*/ #{sql_statement}"
            )
          end
        end

        context 'when append is true' do
          let(:append) { true }

          it 'appends the comment after the sql statement' do
            is_expected.to eq("#{sql_statement} /*dde='dev',ddps='api',ddpv='1.2',dddbs='db_service'*/")
          end
        end
      end

      context 'when `full` mode' do
        let(:mode) { 'full' }
        let(:traceparent) { '00-00000000000000000000000000c0ffee-0000000000000bee-fe' }

        it {
          is_expected.to eq(
            '/*' \
            "dde='dev'," \
            "ddps='api'," \
            "ddpv='1.2'," \
            "dddbs='db_service'," \
            "traceparent='#{traceparent}'*/ " \
            "#{sql_statement}"
          )
        }

        context 'when given a span operation tagged with peer.service' do
          let(:span_op) do
            Datadog::Tracing::SpanOperation.new(
              'sample_span',
              service: 'db_service',
              tags: {'peer.service' => 'db_peer_service'}
            )
          end

          it {
            is_expected.to eq(
              '/*' \
              "dde='dev'," \
              "ddps='api'," \
              "ddpv='1.2'," \
              "ddprs='db_peer_service'," \
              "dddbs='db_peer_service'," \
              "traceparent='#{traceparent}'*/ " \
              "#{sql_statement}"
            )
          }
        end
      end
    end

    describe 'when propagates with `full` mode but tracing is disabled ' do
      before do
        Datadog.configure do |c|
          c.env = 'dev'
          c.service = 'api'
          c.version = '1.2'
          c.tracing.enabled = false
        end

        tracer = instance_double(Datadog::Tracing::Tracer)
        allow(tracer).to receive(:trace) do |_name, &block|
          span_op = Datadog::Tracing::SpanOperation.new('dummy.sql')
          trace_op = Datadog::Tracing::TraceOperation.new
          block&.call(span_op, trace_op)
        end

        allow(Datadog).to receive(:send).with(:components).and_return(
          double(agent_info: agent_info, tracer: tracer)
        )
      end

      let(:mode) { 'full' }

      subject(:dummy_propagation) do
        result = nil

        Datadog::Tracing.trace('dummy.sql') do |span_op, trace_op|
          span_op.service = 'db_service'

          result = described_class.prepend_comment(sql_statement, span_op, trace_op, propagation_mode)
        end

        result
      end

      it do
        is_expected.to eq(
          "/*dde='dev',ddps='api',ddpv='1.2',dddbs='db_service'*/ #{sql_statement}"
        )
      end

      it do
        expect(Datadog.logger).to receive(:warn).with(/`full` mode is aborted, because tracing is disabled/)
        dummy_propagation
      end
    end
  end
end
