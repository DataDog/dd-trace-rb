require 'spec_helper'

require 'time'

require 'datadog/core'
require 'datadog/core/environment/identity'

require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/span_operation'
require 'datadog/tracing/trace_operation'
require 'datadog/tracing/trace_segment'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::TraceOperation do
  subject(:trace_op) { described_class.new(**options) }
  let(:options) { {} }

  shared_context 'trace attributes' do
    let(:options) do
      {
        agent_sample_rate: agent_sample_rate,
        hostname: hostname,
        max_length: max_length,
        name: name,
        origin: origin,
        rate_limiter_rate: rate_limiter_rate,
        resource: resource,
        rule_sample_rate: rule_sample_rate,
        sample_rate: sample_rate,
        sampled: sampled,
        sampling_priority: sampling_priority,
        service: service,
        tags: tags,
        metrics: metrics
      }
    end

    let(:agent_sample_rate) { rand }
    let(:hostname) { 'worker.host' }
    let(:max_length) { 100 }
    let(:name) { 'web.request' }
    let(:origin) { 'synthetics' }
    let(:rate_limiter_rate) { rand }
    let(:resource) { 'reports#show' }
    let(:rule_sample_rate) { rand }
    let(:sample_rate) { rand }
    let(:sampled) { true }
    let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }
    let(:service) { 'billing-api' }
    let(:tags) { { 'foo' => 'bar' }.merge(distributed_tags) }
    let(:metrics) { { 'baz' => 42.0 } }

    let(:distributed_tags) { { '_dd.p.test' => 'value' } }
  end

  shared_examples 'a span with default events' do
    subject(:span_events) { span.send(:events) }
    it { expect(span_events.before_start.subscriptions).to contain_exactly(kind_of(Proc)) }
    it { expect(span_events.after_finish.subscriptions).to contain_exactly(kind_of(Proc)) }
  end

  describe '::new' do
    context 'with no arguments' do
      it 'has default attributes' do
        is_expected.to have_attributes(
          agent_sample_rate: nil,
          hostname: nil,
          id: a_kind_of(Integer),
          max_length: described_class::DEFAULT_MAX_LENGTH,
          name: nil,
          origin: nil,
          parent_span_id: nil,
          rate_limiter_rate: nil,
          resource: nil,
          rule_sample_rate: nil,
          sample_rate: nil,
          sampling_priority: nil,
          service: nil
        )
      end

      it do
        expect(trace_op.send(:meta)).to eq({})
      end

      it do
        expect(trace_op.send(:metrics)).to eq({})
      end
    end

    context 'given' do
      context ':agent_sample_rate' do
        subject(:options) { { agent_sample_rate: agent_sample_rate } }
        let(:agent_sample_rate) { 0.5 }

        it { expect(trace_op.agent_sample_rate).to eq(agent_sample_rate) }
      end

      context ':hostname' do
        subject(:options) { { hostname: hostname } }
        let(:hostname) { 'worker.host' }

        it { expect(trace_op.hostname).to eq(hostname) }
      end

      context ':id' do
        subject(:options) { { id: id } }
        let(:id) { Datadog::Tracing::Utils.next_id }

        it { expect(trace_op.id).to eq(id) }
      end

      context ':max_length' do
        subject(:options) { { max_length: max_length } }
        let(:max_length) { 100 }

        it { expect(trace_op.max_length).to eq(max_length) }
      end

      context ':name' do
        subject(:options) { { name: name } }
        let(:name) { 'sidekiq.job' }

        it { expect(trace_op.name).to eq(name) }
      end

      context ':origin' do
        subject(:options) { { origin: origin } }
        let(:origin) { 'synthetics' }

        it { expect(trace_op.origin).to eq(origin) }
      end

      context ':parent_span_id' do
        subject(:options) { { parent_span_id: parent_span_id } }
        let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

        it { expect(trace_op.parent_span_id).to eq(parent_span_id) }
      end

      context ':rate_limiter_rate' do
        subject(:options) { { rate_limiter_rate: rate_limiter_rate } }
        let(:rate_limiter_rate) { 10.0 }

        it { expect(trace_op.rate_limiter_rate).to eq(rate_limiter_rate) }
      end

      context ':resource' do
        subject(:options) { { resource: resource } }
        let(:resource) { 'generate-billing-reports' }

        it { expect(trace_op.resource).to eq(resource) }
      end

      context ':rule_sample_rate' do
        subject(:options) { { rule_sample_rate: rule_sample_rate } }
        let(:rule_sample_rate) { rand }

        it { expect(trace_op.rule_sample_rate).to eq(rule_sample_rate) }
      end

      context ':sample_rate' do
        subject(:options) { { sample_rate: sample_rate } }
        let(:sample_rate) { rand }

        it { expect(trace_op.sample_rate).to eq(sample_rate) }
      end

      context ':sampled' do
        subject(:options) { { sampled: sampled } }
        let(:sampled) { true }

        it { expect(trace_op.sampled?).to eq(sampled) }
      end

      context ':sampling_priority' do
        subject(:options) { { sampling_priority: sampling_priority } }
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }

        it { expect(trace_op.sampling_priority).to eq(sampling_priority) }
      end

      context ':service' do
        subject(:options) { { service: service } }
        let(:service) { 'billing-worker' }

        it { expect(trace_op.service).to eq(service) }
      end

      context ':tags' do
        subject(:options) { { tags: tags } }
        let(:tags) { { 'foo' => 'bar' } }

        it { expect(trace_op.send(:meta)).to eq({ 'foo' => 'bar' }) }
      end

      context ':metrics' do
        subject(:options) { { metrics: metrics } }
        let(:metrics) { { 'baz' => 42.0 } }

        it { expect(trace_op.send(:metrics)).to eq({ 'baz' => 42.0 }) }
      end
    end
  end

  describe '#full?' do
    subject(:full?) { trace_op.full? }

    it { is_expected.to be false }

    context 'when :max_length is 0' do
      let(:options) { { max_length: 0 } }

      context 'when a trace measures and flushes' do
        it do
          trace_op.measure('parent') do
            expect(trace_op.full?).to be false
          end

          # When finished
          expect(trace_op.full?).to be false

          # When flushed
          trace_op.flush!
          expect(trace_op.full?).to be false
        end
      end

      context 'when a trace builds a span' do
        it do
          # When built
          span = trace_op.build_span('test')
          expect(trace_op.full?).to be false

          # When started
          span.start
          expect(trace_op.full?).to be false

          # When finished
          span.finish
          expect(trace_op.full?).to be false

          # When flushed
          trace_op.flush!
          expect(trace_op.full?).to be false
        end
      end
    end

    context 'when :max_length is non-zero' do
      let(:options) { { max_length: 3 } }

      context 'and number of measured spans' do
        context 'are under :max_length' do
          context 'and a trace measures and flushes' do
            it do
              trace_op.measure('test') do
                trace_op.measure('test') do
                  # When active
                  expect(trace_op.full?).to be false
                end
              end

              # When finished
              expect(trace_op.full?).to be false

              # When flushed
              trace_op.flush!
              expect(trace_op.full?).to be false
            end
          end

          context 'and a trace builds a span' do
            it do
              # When built
              span = trace_op.build_span('test')
              expect(trace_op.full?).to be false

              # When started
              span.start
              expect(trace_op.full?).to be false

              # When finished
              span.finish
              expect(trace_op.full?).to be false

              # When flushed
              trace_op.flush!
              expect(trace_op.full?).to be false
            end
          end
        end

        context 'are at :max_length' do
          context 'and a trace measures and flushes' do
            it do
              trace_op.measure('test') do
                trace_op.measure('test') do
                  trace_op.measure('test') do
                    # When active
                    expect(trace_op.full?).to be true
                  end
                end
              end

              # When finished
              expect(trace_op.full?).to be false

              # When flushed
              trace_op.flush!
              expect(trace_op.full?).to be false
            end
          end

          context 'and a trace builds spans' do
            it do
              # When built
              grandparent_span = trace_op.build_span('grandparent')
              parent_span = trace_op.build_span('parent')
              child_span = trace_op.build_span('child')
              grandchild_span = trace_op.build_span('grandchild')
              expect(trace_op.full?).to be false

              # When started
              grandparent_span.start
              expect(trace_op.full?).to be false
              parent_span.start
              expect(trace_op.full?).to be false
              child_span.start
              expect(trace_op.full?).to be true
              grandchild_span.start
              expect(trace_op.full?).to be true

              # When finished
              grandchild_span.finish
              expect(trace_op.full?).to be true
              child_span.finish
              expect(trace_op.full?).to be false
              parent_span.finish
              expect(trace_op.full?).to be false
              grandparent_span.finish
              expect(trace_op.full?).to be false

              # When flushed
              trace_op.flush!
              expect(trace_op.full?).to be false
            end
          end
        end
      end
    end
  end

  describe '#active_span_count' do
    subject(:active_span_count) { trace_op.active_span_count }

    it { is_expected.to eq 0 }

    context 'when a trace builds a span' do
      it do
        # When built: span is not active
        span = trace_op.build_span('test')
        expect(trace_op.active_span_count).to eq 0

        # When started
        span.start
        expect(trace_op.active_span_count).to eq 1

        # When finished
        span.finish
        expect(trace_op.active_span_count).to eq 0

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span_count).to eq 0
      end
    end

    context 'when a trace measures and flushes' do
      it do
        trace_op.measure('test') do
          # When active
          expect(trace_op.active_span_count).to eq 1
        end

        # When finished
        expect(trace_op.active_span_count).to eq 0

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span_count).to eq 0
      end
    end

    context 'when spans finish out of order' do
      it do
        # When built
        grandparent_span = trace_op.build_span('grandparent')
        parent_span = trace_op.build_span('parent')
        child_span = trace_op.build_span('child')
        expect(trace_op.active_span_count).to eq(0)

        # When started
        grandparent_span.start
        expect(trace_op.active_span_count).to eq(1)
        parent_span.start
        expect(trace_op.active_span_count).to eq(2)
        child_span.start
        expect(trace_op.active_span_count).to eq(3)

        # When finished out of order
        parent_span.finish
        expect(trace_op.active_span_count).to eq(2)
        child_span.finish
        expect(trace_op.active_span_count).to eq(1)
        grandparent_span.finish
        expect(trace_op.active_span_count).to eq(0)

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span_count).to eq(0)
      end
    end
  end

  describe '#finished_span_count' do
    subject(:finished_span_count) { trace_op.finished_span_count }

    it { is_expected.to eq 0 }

    context 'when a trace builds a span' do
      it do
        span = trace_op.build_span('test')
        expect(trace_op.finished_span_count).to eq 0

        # When started
        span.start
        expect(trace_op.finished_span_count).to eq 0

        # When finished
        span.finish
        expect(trace_op.finished_span_count).to eq 1

        # When flushed
        trace_op.flush!
        expect(trace_op.finished_span_count).to eq 0
      end
    end

    context 'when a trace measures and flushes' do
      it do
        trace_op.measure('test') do
          # When active
          expect(trace_op.finished_span_count).to eq 0
        end

        # When finished
        expect(trace_op.finished_span_count).to eq 1

        # When flushed
        trace_op.flush!
        expect(trace_op.finished_span_count).to eq 0
      end
    end

    context 'when spans finish out of order' do
      it do
        # When built
        grandparent_span = trace_op.build_span('grandparent')
        parent_span = trace_op.build_span('parent')
        child_span = trace_op.build_span('child')
        expect(trace_op.finished_span_count).to eq(0)

        # When started
        grandparent_span.start
        expect(trace_op.finished_span_count).to eq(0)
        parent_span.start
        expect(trace_op.finished_span_count).to eq(0)
        child_span.start
        expect(trace_op.finished_span_count).to eq(0)

        # When finished out of order
        parent_span.finish
        expect(trace_op.finished_span_count).to eq(1)
        child_span.finish
        expect(trace_op.finished_span_count).to eq(2)
        grandparent_span.finish
        expect(trace_op.finished_span_count).to eq(3)

        # When flushed
        trace_op.flush!
        expect(trace_op.finished_span_count).to eq(0)
      end
    end
  end

  describe '#active_span' do
    subject(:active_span) { trace_op.active_span }

    it { is_expected.to be nil }

    context 'when a trace builds a span' do
      it do
        # When built: span is not active
        span = trace_op.build_span('test')
        expect(trace_op.active_span).to be nil

        # When started
        span.start
        expect(trace_op.active_span).to be span

        # When finished
        span.finish
        expect(trace_op.active_span).to be nil

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span).to be nil
      end
    end

    context 'when a trace measures and flushes' do
      it do
        trace_op.measure('parent') do |parent_span|
          expect(trace_op.active_span).to be parent_span

          trace_op.measure('child') do |child_span|
            expect(trace_op.active_span).to be child_span
          end

          expect(trace_op.active_span).to be parent_span
        end

        # When finished
        expect(trace_op.active_span).to be nil

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span).to be nil
      end
    end

    context 'when spans finish out of order' do
      it do
        # When built: span is not active
        grandparent_span = trace_op.build_span('grandparent')
        parent_span = trace_op.build_span('parent')
        child_span = trace_op.build_span('child')
        expect(trace_op.active_span).to be nil

        # When started
        grandparent_span.start
        expect(trace_op.active_span).to be grandparent_span
        parent_span.start
        expect(trace_op.active_span).to be parent_span
        child_span.start
        expect(trace_op.active_span).to be child_span

        # When finished out of order
        parent_span.finish
        expect(trace_op.active_span).to be grandparent_span
        child_span.finish
        expect(trace_op.active_span).to be grandparent_span
        grandparent_span.finish
        expect(trace_op.active_span).to be nil

        # When flushed
        trace_op.flush!
        expect(trace_op.active_span).to be nil
      end
    end
  end

  describe '#finished?' do
    subject(:finished?) { trace_op.finished? }

    it { is_expected.to be false }

    context 'when a trace builds a span' do
      it do
        # When built: span is not active
        span = trace_op.build_span('test')
        expect(trace_op.finished?).to be false

        # When started
        span.start
        expect(trace_op.finished?).to be false

        # When finished
        span.finish
        expect(trace_op.finished?).to be true

        # When flushed
        trace_op.flush!
        expect(trace_op.finished?).to be true
      end
    end

    context 'when a trace measures and flushes' do
      it do
        trace_op.measure('parent') do
          expect(trace_op.finished?).to be false

          trace_op.measure('child') do
            expect(trace_op.finished?).to be false
          end

          expect(trace_op.finished?).to be false
        end

        # When finished
        expect(trace_op.finished?).to be true

        # When flushed
        trace_op.flush!
        expect(trace_op.finished?).to be true
      end
    end

    context 'when spans finish out of order' do
      it do
        # When built
        grandparent_span = trace_op.build_span('grandparent')
        parent_span = trace_op.build_span('parent')
        child_span = trace_op.build_span('child')
        expect(trace_op.finished?).to be false

        # When started
        grandparent_span.start
        expect(trace_op.finished?).to be false
        parent_span.start
        expect(trace_op.finished?).to be false
        child_span.start
        expect(trace_op.finished?).to be false

        # When finished out of order
        parent_span.finish
        expect(trace_op.finished?).to be false
        child_span.finish
        expect(trace_op.finished?).to be false
        grandparent_span.finish
        expect(trace_op.finished?).to be true

        # When flushed
        trace_op.flush!
        expect(trace_op.finished?).to be true
      end
    end
  end

  describe '#sampled?' do
    subject(:sampled?) { trace_op.sampled? }

    it 'traces are sampled by default' do
      is_expected.to be true
    end

    context 'when :sampled is set in initializer' do
      let(:options) { { sampled: false } }
      it { is_expected.to be false }
    end

    [true, false].each do |sampled|
      context "when :sampled is set to #{sampled}" do
        let(:options) { { sampled: sampled } }

        context 'when :sampling_priority is set to' do
          let(:options) { super().merge(sampling_priority: sampling_priority) }

          context 'AUTO_KEEP' do
            let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }
            it { is_expected.to be true }
          end

          context 'AUTO_REJECT' do
            let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT }
            it { is_expected.to be sampled }
          end

          context 'USER_KEEP' do
            let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }
            it { is_expected.to be true }
          end

          context 'USER_REJECT' do
            let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT }
            it { is_expected.to be sampled }
          end
        end
      end
    end

    context 'when #sampled and #sampling priority' do
      context 'are both set to matching values' do
        context 'with sampled: true and priority: keep' do
          before do
            trace_op.sampled = true
            trace_op.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          end

          it { is_expected.to be true }
        end

        context 'with sampled: false and priority: reject' do
          before do
            trace_op.sampled = false
            trace_op.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          end

          it { is_expected.to be false }
        end
      end

      context 'are both set to conflicting values' do
        context 'with sampled: false and priority: keep' do
          before do
            trace_op.sampled = false
            trace_op.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP
          end

          it { is_expected.to be true }
        end

        context 'with sampled: true and priority: reject' do
          before do
            trace_op.sampled = true
            trace_op.sampling_priority = Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT
          end

          it { is_expected.to be true }
        end
      end
    end
  end

  describe '#priority_sampled?' do
    subject(:priority_sampled?) { trace_op.priority_sampled? }

    it { is_expected.to be false }

    context 'when :sampling_priority is set to' do
      let(:options) { { sampling_priority: sampling_priority } }

      context 'AUTO_KEEP' do
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_KEEP }
        it { is_expected.to be true }
      end

      context 'AUTO_REJECT' do
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::AUTO_REJECT }
        it { is_expected.to be false }
      end

      context 'USER_KEEP' do
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP }
        it { is_expected.to be true }
      end

      context 'USER_REJECT' do
        let(:sampling_priority) { Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT }
        it { is_expected.to be false }
      end
    end
  end

  describe '#keep!' do
    subject(:keep!) { trace_op.keep! }

    it 'sets sampling mechanism to MANUAL' do
      expect { keep! }
        .to change { trace_op.get_tag('_dd.p.dm') }
        .from(nil)
        .to('-4')
    end

    it 'sets priority sampling to USER_KEEP' do
      expect { keep! }
        .to change { trace_op.sampling_priority }
        .from(nil)
        .to(Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP)
    end

    it 'sets sampled? to true' do
      expect { keep! }
        .to_not change { trace_op.sampled? }
        .from(true)
    end

    context 'when #sampled was true' do
      before { trace_op.sampled = true }

      it 'does not modify sampled?' do
        expect { keep! }
          .to_not change { trace_op.sampled? }
          .from(true)
      end
    end

    context 'when #sampled was false' do
      before { trace_op.sampled = false }

      it do
        expect { keep! }
          .to change { trace_op.sampled? }
          .from(false)
          .to(true)
      end
    end
  end

  describe '#reject!' do
    subject(:reject!) { trace_op.reject! }

    it 'sets sampling mechanism to MANUAL' do
      expect { reject! }
        .to change { trace_op.get_tag('_dd.p.dm') }
        .from(nil)
        .to('-4')
    end

    it 'sets priority sampling to USER_REJECT' do
      expect { reject! }
        .to change { trace_op.sampling_priority }
        .from(nil)
        .to(Datadog::Tracing::Sampling::Ext::Priority::USER_REJECT)
    end

    it 'does not modify sampled?' do
      expect { reject! }
        .to change { trace_op.sampled? }
        .from(true).to(false)
    end

    context 'when #sampled was true' do
      before { trace_op.sampled = true }

      it 'sets sampled? to false' do
        expect { reject! }
          .to change { trace_op.sampled? }
          .from(true)
          .to(false)
      end
    end

    context 'when #sampled was false' do
      before { trace_op.sampled = false }

      it 'does not modify sampled?' do
        expect { reject! }
          .to_not change { trace_op.sampled? }
          .from(false)
      end
    end
  end

  shared_examples 'root span derived attribute' do |attribute_name|
    subject(:attribute) { trace_op.send(attribute_name) }

    context 'when nothing is set' do
      it { is_expected.to be nil }
    end

    context "when the trace has a root span with a #{attribute_name}" do
      let(:root_span_value) { "root_span.#{attribute_name}" }

      before do
        trace_op.measure('web.request') do |span|
          span.send("#{attribute_name}=", root_span_value)
        end
      end

      it { is_expected.to eq root_span_value }
    end

    context "when #{attribute_name} is set" do
      let(:trace_value) { "trace.#{attribute_name}" }

      before { trace_op.send("#{attribute_name}=", trace_value) }

      it { is_expected.to eq trace_value }
    end

    context "when #{attribute_name} is set and root span has been added" do
      let(:trace_value) { "trace.#{attribute_name}" }
      let(:root_span_value) { "root_span.#{attribute_name}" }

      before do
        trace_op.send("#{attribute_name}=", trace_value)
        trace_op.measure('web.request') do |span|
          span.send("#{attribute_name}=", root_span_value)
        end
      end

      it { is_expected.to eq trace_value }
    end
  end

  describe '#name' do
    it_behaves_like 'root span derived attribute', :name
  end

  describe '#resource' do
    it_behaves_like 'root span derived attribute', :resource
  end

  describe '#resource_override?' do
    subject { trace_op.resource_override? }

    context 'when initialized without `resource`' do
      it { is_expected.to eq(false) }
    end

    context 'when initialized with `resource` as `nil`' do
      let(:options) { { resource: nil } }
      it { is_expected.to eq(false) }
    end

    context 'when initialized with `resource` as `GET 200`' do
      let(:options) { { resource: 'GET 200' } }
      it { is_expected.to eq(true) }
    end

    context 'when set `resource` as `nil`' do
      it do
        trace_op.resource = nil

        is_expected.to eq(false)
      end
    end

    context 'when set `resource` as `UsersController#show`' do
      it do
        trace_op.resource = 'UsersController#show'

        is_expected.to eq(true)
      end
    end
  end

  describe '#service' do
    it_behaves_like 'root span derived attribute', :service
  end

  describe '#get_tag' do
    before do
      trace_op.set_tag('foo', 'bar')
    end

    it 'gets tag set on trace' do
      expect(trace_op.get_tag('foo')).to eq('bar')
    end

    it 'gets unset tag as nil' do
      expect(trace_op.get_tag('unset')).to be_nil
    end
  end

  describe '#set_metric' do
    it 'sets metrics' do
      trace_op.set_metric('foo', 42)
      trace_op.measure('top') {}

      trace = trace_op.flush!

      expect(trace.send(:metrics)['foo']).to eq(42)
    end
  end

  describe '#set_tag' do
    it 'sets tag on trace before a measurement' do
      trace_op.set_tag('foo', 'bar')
      trace_op.measure('top') {}

      trace = trace_op.flush!

      expect(trace.send(:meta)['foo']).to eq('bar')
    end

    it 'sets tag on trace after a measurement' do
      trace_op.measure('top') {}
      trace_op.set_tag('foo', 'bar')

      trace = trace_op.flush!

      expect(trace.send(:meta)['foo']).to eq('bar')
    end

    it 'sets tag on trace from a measurement' do
      trace_op.measure('top') do
        trace_op.set_tag('foo', 'bar')
      end

      trace = trace_op.flush!

      expect(trace.send(:meta)['foo']).to eq('bar')
    end

    it 'sets tag on trace from a nested measurement' do
      trace_op.measure('grandparent') do
        trace_op.measure('parent') do
          trace_op.set_tag('foo', 'bar')
        end
      end

      trace = trace_op.flush!

      expect(trace.spans).to have(2).items
      expect(trace.spans.map(&:name)).to include('parent')
      expect(trace.send(:meta)['foo']).to eq('bar')
    end

    it 'sets metrics' do
      trace_op.set_tag('foo', 42)
      trace_op.measure('top') {}

      trace = trace_op.flush!

      expect(trace.send(:metrics)['foo']).to eq(42)
    end

    context 'with partial flushing' do
      subject(:flush!) { trace_op.flush! }
      let(:trace) { flush! }

      it 'sets tag on trace from a nested measurement' do
        trace_op.measure('grandparent') do
          trace_op.measure('parent') do
            trace_op.set_tag('foo', 'bar')
          end
          flush!
        end

        expect(trace.spans).to have(1).items
        expect(trace.spans.map(&:name)).to include('parent')
        expect(trace.send(:meta)['foo']).to eq('bar')

        final_flush = trace_op.flush!
        expect(final_flush.spans).to have(1).items
        expect(final_flush.spans.map(&:name)).to include('grandparent')
        expect(final_flush.send(:meta)['foo']).to eq('bar')
      end
    end
  end

  describe '#build_span' do
    subject(:build_span) { trace_op.build_span(span_name, **span_options) }
    let(:span_name) { 'web.request' }
    let(:span_options) { {} }

    let(:span) { build_span }

    it { is_expected.to be_a_kind_of(Datadog::Tracing::SpanOperation) }

    context 'given' do
      context ':events' do
        let(:span_options) { { events: events } }

        context 'as nil' do
          let(:events) { nil }

          it_behaves_like 'a span with default events'
        end

        context 'as Datadog::Tracing::SpanOperation::Events' do
          let(:events) { Datadog::Tracing::SpanOperation::Events.new }

          it_behaves_like 'a span with default events' do
            it { expect(span_events).to be(events) }
          end
        end
      end

      context ':on_error' do
        let(:span_options) { { on_error: on_error } }

        context 'as nil' do
          let(:on_error) { nil }

          it_behaves_like 'a span with default events'
        end

        context 'as Datadog::Tracing::SpanOperation::Events' do
          it_behaves_like 'a span with default events' do
            let(:on_error) { proc { |*args| callback_spy.call(*args) } }
            let(:callback_spy) { spy('callback spy') }

            context 'when #on_error is published' do
              let(:event_args) do
                [
                  instance_double(Datadog::Tracing::SpanOperation),
                  instance_double(StandardError)
                ]
              end

              it do
                expect(callback_spy).to receive(:call).with(*event_args)
                span_events.on_error.publish(*event_args)
              end
            end
          end
        end
      end

      context ':resource' do
        let(:span_options) { { resource: resource } }

        context 'as nil' do
          let(:resource) { nil }
          it { expect(span.resource).to eq(span_name) }
        end

        context 'as String' do
          let(:resource) { 'reports#show' }
          it { expect(span.resource).to eq(resource) }
        end
      end

      context ':service' do
        let(:span_options) { { service: service } }

        context 'as nil' do
          let(:service) { nil }
          it { expect(span.service).to be nil }

          context 'but the trace has an active span with service' do
            let(:active_service) { 'web-worker' }

            before do
              trace_op.measure('parent', service: active_service) { build_span }
            end

            # It should never inherit from a parent span
            it { expect(span.service).to be nil }
          end
        end

        context 'as String' do
          let(:service) { 'billing-api' }
          it { expect(span.service).to eq(service) }
        end
      end

      context ':start_time' do
        let(:span_options) { { start_time: start_time } }

        context 'as nil' do
          let(:start_time) { nil }
          it { expect(span.start_time).to be nil }
        end

        context 'as DateTime' do
          let(:start_time) { Time.now }
          it { expect(span.start_time).to eq(start_time) }
          it { expect(span.started?).to be true }
        end
      end

      context ':tags' do
        let(:span_options) { { tags: tags } }

        context 'as nil' do
          let(:tags) { nil }
          it { expect(span.send(:meta)).to eq({}) }
        end

        context 'as Hash' do
          let(:tags) { { foo: 'bar' } }
          it { expect(span.send(:meta)).to include('foo' => 'bar') }
        end
      end
    end

    context 'when the trace' do
      context 'is empty' do
        it do
          is_expected.to have_attributes(
            id: a_kind_of(Integer),
            parent_id: 0,
            resource: span_name,
            service: nil,
            start_time: nil,
            trace_id: trace_op.id,
            type: nil
          )
        end
      end

      context 'has already built a span' do
        context 'that has not been started' do
          let(:parent_span) { trace_op.build_span('parent') }

          before { parent_span }

          it do
            is_expected.to have_attributes(
              id: a_kind_of(Integer),
              parent_id: 0,
              resource: span_name,
              service: nil,
              start_time: nil,
              trace_id: trace_op.id,
              type: nil
            )
          end
        end

        context 'that has been started' do
          let(:parent_span) { trace_op.build_span('parent').start }

          before { parent_span }

          it do
            is_expected.to have_attributes(
              id: a_kind_of(Integer),
              parent_id: parent_span.id,
              resource: span_name,
              service: nil,
              start_time: nil,
              trace_id: trace_op.id,
              type: nil
            )
          end
        end

        context 'that has been finished' do
          let(:parent_span) { trace_op.build_span('parent').start.finish }

          before { parent_span }

          it do
            is_expected.to have_attributes(
              id: a_kind_of(Integer),
              parent_id: 0,
              resource: span_name,
              service: nil,
              start_time: nil,
              trace_id: trace_op.id,
              type: nil
            )
          end
        end
      end

      context 'is measuring another span' do
        before do
          trace_op.measure('parent') do |parent|
            @parent = parent
            build_span
          end
        end

        it do
          is_expected.to have_attributes(
            id: a_kind_of(Integer),
            parent_id: @parent.id,
            resource: span_name,
            service: nil,
            start_time: nil,
            trace_id: trace_op.id,
            type: nil
          )
        end
      end
    end

    context 'when building the span fails' do
      let(:span_options) { { resource: 'my-span' } }
      let(:error) { error_class.new('error message') }

      before do
        allow(Datadog::Tracing::SpanOperation).to receive(:new) do
          # Unstub (so it only raises an error once)
          allow(Datadog::Tracing::SpanOperation).to receive(:new).and_call_original

          # Trigger error
          raise error
        end

        allow(Datadog.logger).to receive(:debug)
      end

      context 'with a StandardError' do
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }

        it do
          expect { build_span }.to_not raise_error
          expect(span).to be_a_kind_of(Datadog::Tracing::SpanOperation)
          expect(span.trace_id).to_not eq(trace_op.id)
          expect(Datadog.logger).to have_lazy_debug_logged(/Failed to build new span/)
        end
      end

      context 'with a Exception' do
        # rubocop:disable Lint/InheritException
        let(:error_class) { stub_const('TestError', Class.new(Exception)) }
        # rubocop:enable Lint/InheritException

        it do
          expect { build_span }.to raise_error(error)
          expect(Datadog.logger).to_not have_lazy_debug_logged(/Failed to build new span/)
        end
      end
    end
  end

  describe '#measure' do
    subject(:measure) { trace_op.measure(span_name, **span_options, &block) }
    let(:span_name) { 'web.request' }
    let(:span_options) { {} }
    let(:block) { proc { |span| @span = span } }

    # Helper to measure and expose the created span
    def span
      measure
      @span
    end

    context 'given a block' do
      it 'yields the new span and trace to the block' do
        expect { |b| trace_op.measure(span_name, &b) }.to yield_with_args(
          kind_of(Datadog::Tracing::SpanOperation),
          trace_op
        )
      end

      it 'returns the value of the block' do
        expect(
          trace_op.measure(span_name) { :return_value }
        ).to be(:return_value)
      end
    end

    context 'when the trace' do
      context 'is empty' do
        it do
          expect(span).to have_attributes(
            end_time: kind_of(Time),
            finished?: true,
            id: a_kind_of(Integer),
            parent_id: 0,
            resource: span_name,
            service: nil,
            start_time: kind_of(Time),
            trace_id: trace_op.id,
            type: nil
          )
        end
      end

      context 'is full' do
        let(:options) { { max_length: 2 } }
        let(:block) { proc { |*args| block_spy.call(*args) } }
        let(:block_spy) { spy('block spy') }

        before do
          allow(block_spy).to receive(:call)

          trace_op.measure('grandparent') do
            trace_op.measure('parent') do
              measure
            end
          end
        end

        it 'yields a dummy trace and span' do
          expect(block_spy).to have_received(:call) do |span, trace|
            expect(span).to be_a_kind_of(Datadog::Tracing::SpanOperation)
            expect(span.trace_id).to_not eq(trace_op.id)

            expect(trace).to be_a_kind_of(described_class)
            expect(trace.id).to_not be trace_op
          end
        end

        it 'ignores the span' do
          expect(trace_op.finished?).to be true
          expect(trace_op.finished_span_count).to eq(2)
        end
      end

      context 'is finished' do
        let(:options) { { max_length: 2 } }
        let(:block) { proc { |*args| block_spy.call(*args) } }
        let(:block_spy) { spy('block spy') }

        before do
          allow(block_spy).to receive(:call)

          trace_op.measure('grandparent') do
            # Do something
          end

          measure
        end

        it 'yields a dummy trace and span' do
          expect(block_spy).to have_received(:call) do |span, trace|
            expect(span).to be_a_kind_of(Datadog::Tracing::SpanOperation)
            expect(span.trace_id).to_not eq(trace_op.id)

            expect(trace).to be_a_kind_of(described_class)
            expect(trace.id).to_not be trace_op
          end
        end

        it 'ignores the span' do
          expect(trace_op.finished?).to be true
          expect(trace_op.finished_span_count).to eq(1)
        end
      end

      context 'has already built a span' do
        context 'that has not been started' do
          let(:parent_span) { trace_op.build_span('parent') }

          before { parent_span }

          it do
            expect(span).to have_attributes(
              end_time: kind_of(Time),
              finished?: true,
              id: a_kind_of(Integer),
              parent_id: 0,
              resource: span_name,
              service: nil,
              start_time: kind_of(Time),
              trace_id: trace_op.id,
              type: nil
            )
          end
        end

        context 'that has been started' do
          let(:parent_span) { trace_op.build_span('parent').start }

          before { parent_span }

          it do
            expect(span).to have_attributes(
              end_time: kind_of(Time),
              finished?: true,
              id: a_kind_of(Integer),
              parent_id: parent_span.id,
              resource: span_name,
              service: nil,
              start_time: kind_of(Time),
              trace_id: trace_op.id,
              type: nil
            )
          end
        end

        context 'that has been finished' do
          let(:parent_span) { trace_op.build_span('parent').start.finish }

          let(:block) { proc { |*args| block_spy.call(*args) } }
          let(:block_spy) { spy('block spy') }

          before do
            allow(block_spy).to receive(:call)
            parent_span
            measure
          end

          it 'yields a dummy trace and span' do
            expect(block_spy).to have_received(:call) do |span, trace|
              expect(span).to be_a_kind_of(Datadog::Tracing::SpanOperation)
              expect(span.trace_id).to_not eq(trace_op.id)

              expect(trace).to be_a_kind_of(described_class)
              expect(trace.id).to_not be trace_op
            end
          end

          it 'ignores the span' do
            expect(trace_op.finished?).to be true
            expect(trace_op.finished_span_count).to eq(1)
          end
        end
      end

      context 'is measuring another span' do
        before do
          trace_op.measure('parent') do |parent|
            @parent = parent
            measure
          end
        end

        it do
          expect(span).to have_attributes(
            end_time: kind_of(Time),
            finished?: true,
            id: a_kind_of(Integer),
            parent_id: @parent.id,
            resource: span_name,
            service: nil,
            start_time: kind_of(Time),
            trace_id: trace_op.id,
            type: nil
          )
        end
      end

      context 'resource' do
        let(:trace_steps) { {} }

        context 'is inherited from the root span' do
          it 'is visible at any point in the trace' do
            expect(trace_op.resource).to be nil

            trace_op.measure('web.request') do |root_span|
              expect(trace_op.resource).to eq('web.request')
              expect(root_span.resource).to eq('web.request')

              root_span.resource = '/articles/?'

              expect(trace_op.resource).to eq('/articles/?')
              expect(root_span.resource).to eq('/articles/?')

              trace_op.measure('controller.action') do |child_span|
                expect(trace_op.resource).to eq('/articles/?')
                expect(child_span.resource).to eq('controller.action')

                child_span.resource = 'Articles#show'

                expect(trace_op.resource).to eq('/articles/?')
                expect(child_span.resource).to eq('Articles#show')
              end

              expect(trace_op.resource).to eq('/articles/?')
              expect(root_span.resource).to eq('/articles/?')
            end

            expect(trace_op.resource).to eq('/articles/?')
          end
        end

        context 'is overridden by the child span' do
          it 'child span resource is persisted on the trace' do
            expect(trace_op.resource).to be nil

            trace_op.measure('web.request') do |root_span|
              expect(trace_op.resource).to eq('web.request')
              expect(root_span.resource).to eq('web.request')

              root_span.resource = '/articles/?'

              expect(trace_op.resource).to eq('/articles/?')
              expect(root_span.resource).to eq('/articles/?')

              trace_op.measure('controller.action') do |child_span|
                expect(trace_op.resource).to eq('/articles/?')
                expect(child_span.resource).to eq('controller.action')

                child_span.resource = 'Articles#show'

                expect(trace_op.resource).to eq('/articles/?')
                expect(child_span.resource).to eq('Articles#show')

                # Override the trace resource
                trace_op.resource = child_span.resource

                expect(trace_op.resource).to eq('Articles#show')
                expect(child_span.resource).to eq('Articles#show')
              end

              expect(trace_op.resource).to eq('Articles#show')
              expect(root_span.resource).to eq('/articles/?')
            end

            expect(trace_op.resource).to eq('Articles#show')
          end
        end
      end
    end
  end

  describe '#flush!' do
    subject(:flush!) { trace_op.flush! }
    let(:trace) { flush! }

    context 'when the trace' do
      include_context 'trace attributes'

      context 'is empty' do
        it { is_expected.to be_a_kind_of(Datadog::Tracing::TraceSegment) }
        it { expect(trace.spans).to have(0).items }

        it do
          expect(trace).to have_attributes(
            agent_sample_rate: agent_sample_rate,
            hostname: hostname,
            id: trace_op.id,
            lang: Datadog::Core::Environment::Identity.lang,
            name: name,
            origin: origin,
            process_id: Datadog::Core::Environment::Identity.pid,
            rate_limiter_rate: rate_limiter_rate,
            resource: resource,
            rule_sample_rate: rule_sample_rate,
            runtime_id: Datadog::Core::Environment::Identity.id,
            sample_rate: sample_rate,

            sampling_priority: sampling_priority,
            service: service
          )
        end
      end

      context 'is finished' do
        before do
          trace_op.measure(
            'grandparent',
            service: 'boo',
            resource: 'far',
            type: 'faz'
          ) do
            trace_op.measure(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ) do
              # Do something
            end
          end
        end

        it 'flushes a trace with all spans' do
          expect(trace_op.finished?).to be true

          is_expected.to be_a_kind_of(Datadog::Tracing::TraceSegment)
          expect(trace.spans).to have(2).items
          expect(trace.spans.map(&:name)).to include('parent', 'grandparent')
          expect(trace.send(:root_span_id)).to be_a_kind_of(Integer)

          expect(trace).to have_attributes(
            agent_sample_rate: agent_sample_rate,
            hostname: hostname,
            id: trace_op.id,
            lang: Datadog::Core::Environment::Identity.lang,
            name: name,
            origin: origin,
            process_id: Datadog::Core::Environment::Identity.pid,
            rate_limiter_rate: rate_limiter_rate,
            resource: resource,
            rule_sample_rate: rule_sample_rate,
            runtime_id: Datadog::Core::Environment::Identity.id,
            sample_rate: sample_rate,

            sampling_priority: sampling_priority,
            service: service
          )
        end

        it 'does not yield duplicate spans' do
          expect(trace_op.flush!.spans).to have(2).items
          expect(trace_op.flush!.spans).to have(0).items
        end

        context 'with a block' do
          subject(:flush!) { trace_op.flush! { |spans| spans } }

          it 'yields spans' do
            expect { |b| trace_op.flush!(&b) }.to yield_with_args(
              [
                have_attributes(name: 'parent'),
                have_attributes(name: 'grandparent')
              ]
            )
          end

          it 'uses block return as new span list' do
            new_list = [double('span')]
            expect(trace_op.flush! { new_list }).to have_attributes(spans: new_list)
          end
        end
      end

      context 'is partially finished' do
        it 'flushes spans as they finish' do
          trace_op.measure('grandparent') do
            trace_op.measure('parent') do
              # Do something
            end

            # Partial flush
            flush!
          end

          # Verify partial flush
          is_expected.to be_a_kind_of(Datadog::Tracing::TraceSegment)
          expect(trace.spans).to have(1).items
          expect(trace.spans.map(&:name)).to include('parent')
          expect(trace.send(:root_span_id)).to be nil

          expect(trace).to have_attributes(
            agent_sample_rate: agent_sample_rate,
            hostname: hostname,
            id: trace_op.id,
            lang: Datadog::Core::Environment::Identity.lang,
            name: name,
            origin: origin,
            process_id: Datadog::Core::Environment::Identity.pid,
            rate_limiter_rate: rate_limiter_rate,
            resource: resource,
            rule_sample_rate: rule_sample_rate,
            runtime_id: Datadog::Core::Environment::Identity.id,
            sample_rate: sample_rate,

            sampling_priority: sampling_priority,
            service: service
          )

          # There should be finished spans pending
          expect(trace_op.finished?).to be true
          expect(trace_op.finished_span_count).to eq(1)

          # Verify final flush
          final_flush = trace_op.flush!
          expect(final_flush.spans).to have(1).items
          expect(final_flush.spans.map(&:name)).to include('grandparent')
          expect(final_flush.send(:root_span_id)).to be_a_kind_of(Integer)

          expect(final_flush).to have_attributes(
            agent_sample_rate: agent_sample_rate,
            hostname: hostname,
            id: trace_op.id,
            lang: Datadog::Core::Environment::Identity.lang,
            name: name,
            origin: origin,
            process_id: Datadog::Core::Environment::Identity.pid,
            rate_limiter_rate: rate_limiter_rate,
            resource: resource,
            rule_sample_rate: rule_sample_rate,
            runtime_id: Datadog::Core::Environment::Identity.id,
            sample_rate: sample_rate,

            sampling_priority: sampling_priority,
            service: service
          )

          # Make sure its actually empty
          expect(trace_op.flush!.spans).to have(0).items
        end
      end
    end
  end

  describe '#to_digest' do
    subject(:to_digest) { trace_op.to_digest }
    let(:digest) { to_digest }

    context 'when the trace' do
      context 'is empty' do
        it { is_expected.to be_a_kind_of(Datadog::Tracing::TraceDigest) }

        context 'and the trace was not initialized with any attributes' do
          it do
            is_expected.to have_attributes(
              span_id: nil,
              span_name: nil,
              span_resource: nil,
              span_service: nil,
              span_type: nil,
              trace_distributed_tags: {},
              trace_hostname: nil,
              trace_id: trace_op.id,
              trace_name: nil,
              trace_origin: nil,
              trace_process_id: Datadog::Core::Environment::Identity.pid,
              trace_resource: nil,
              trace_runtime_id: Datadog::Core::Environment::Identity.id,

              trace_sampling_priority: nil,
              trace_service: nil
            )
          end
        end

        context 'and the trace was initialized with attributes' do
          include_context 'trace attributes'

          it do
            is_expected.to have_attributes(
              span_id: nil,
              span_name: nil,
              span_resource: nil,
              span_service: nil,
              span_type: nil,
              trace_distributed_tags: distributed_tags,
              trace_hostname: be_a_frozen_copy_of(hostname),
              trace_id: trace_op.id,
              trace_name: be_a_frozen_copy_of(name),
              trace_origin: be_a_frozen_copy_of(origin),
              trace_process_id: Datadog::Core::Environment::Identity.pid,
              trace_resource: be_a_frozen_copy_of(resource),
              trace_runtime_id: Datadog::Core::Environment::Identity.id,
              trace_sampling_priority: sampling_priority,
              trace_service: be_a_frozen_copy_of(service)
            )
          end
        end

        context 'but :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(digest.span_id).to eq(parent_span_id) }
        end
      end

      context 'is measuring an operation' do
        before do
          trace_op.measure(
            'grandparent',
            service: 'boo',
            resource: 'far',
            type: 'faz'
          ) do
            trace_op.measure(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ) do |parent, trace|
              @parent = parent
              trace.set_tag('_dd.p.test', 'value')
              to_digest
            end
          end
        end

        it do
          is_expected.to have_attributes(
            span_id: @parent.id,
            span_name: 'parent',
            span_resource: 'bar',
            span_service: 'foo',
            span_type: 'baz',
            trace_distributed_tags: { '_dd.p.test' => 'value' },
            trace_hostname: nil,
            trace_id: trace_op.id,
            trace_name: 'grandparent',
            trace_origin: nil,
            trace_process_id: Datadog::Core::Environment::Identity.pid,
            trace_resource: 'far',
            trace_runtime_id: Datadog::Core::Environment::Identity.id,

            trace_sampling_priority: nil,
            trace_service: 'boo'
          )
        end

        context 'and :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(digest.span_id).to eq(@parent.id) }
        end
      end

      context 'has built a span' do
        context 'that has not started' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            )
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              span_id: nil,
              span_name: nil,
              span_resource: nil,
              span_service: nil,
              span_type: nil,
              trace_distributed_tags: {},
              trace_hostname: nil,
              trace_id: trace_op.id,
              trace_name: nil,
              trace_origin: nil,
              trace_process_id: Datadog::Core::Environment::Identity.pid,
              trace_resource: nil,
              trace_runtime_id: Datadog::Core::Environment::Identity.id,

              trace_sampling_priority: nil,
              trace_service: nil
            )
          end
        end

        context 'that has started' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ).start
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              span_id: parent_span.id,
              span_name: 'parent',
              span_resource: 'bar',
              span_service: 'foo',
              span_type: 'baz',
              trace_distributed_tags: {},
              trace_hostname: nil,
              trace_id: trace_op.id,
              trace_name: 'parent',
              trace_origin: nil,
              trace_process_id: Datadog::Core::Environment::Identity.pid,
              trace_resource: 'bar',
              trace_runtime_id: Datadog::Core::Environment::Identity.id,

              trace_sampling_priority: nil,
              trace_service: 'foo'
            )
          end
        end

        context 'that has finished' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ).start.finish
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              span_id: nil,
              span_name: nil,
              span_resource: nil,
              span_service: nil,
              span_type: nil,
              trace_distributed_tags: {},
              trace_hostname: nil,
              trace_id: trace_op.id,
              trace_name: 'parent',
              trace_origin: nil,
              trace_process_id: Datadog::Core::Environment::Identity.pid,
              trace_resource: 'bar',
              trace_runtime_id: Datadog::Core::Environment::Identity.id,

              trace_sampling_priority: nil,
              trace_service: 'foo'
            )
          end
        end
      end

      context 'is finished' do
        before do
          trace_op.measure(
            'grandparent',
            service: 'boo',
            resource: 'far',
            type: 'faz'
          ) do
            trace_op.measure(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ) do |parent|
              # Do something
            end
          end
        end

        it do
          is_expected.to have_attributes(
            span_id: nil,
            span_name: nil,
            span_resource: nil,
            span_service: nil,
            span_type: nil,
            trace_distributed_tags: {},
            trace_hostname: nil,
            trace_id: trace_op.id,
            trace_name: 'grandparent',
            trace_origin: nil,
            trace_process_id: Datadog::Core::Environment::Identity.pid,
            trace_resource: 'far',
            trace_runtime_id: Datadog::Core::Environment::Identity.id,

            trace_sampling_priority: nil,
            trace_service: 'boo'
          )
        end

        context 'and :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(digest.span_id).to be nil }
        end
      end
    end
  end

  describe '#fork_clone' do
    subject(:fork_clone) { trace_op.fork_clone }
    let(:new_trace_op) { fork_clone }

    context 'when the trace' do
      context 'is empty' do
        it { is_expected.to be_a_kind_of(described_class) }

        context 'and trace attributes are defined' do
          include_context 'trace attributes'

          it do
            is_expected.to have_attributes(
              agent_sample_rate: agent_sample_rate,
              id: trace_op.id,
              max_length: trace_op.max_length,
              name: be_a_copy_of(name),
              origin: be_a_copy_of(origin),
              parent_span_id: trace_op.parent_span_id,
              rate_limiter_rate: rate_limiter_rate,
              resource: be_a_copy_of(resource),
              rule_sample_rate: rule_sample_rate,
              sample_rate: sample_rate,
              sampled?: sampled,
              sampling_priority: sampling_priority,
              service: be_a_copy_of(service)
            )
          end

          it 'maintains the same tags' do
            expect(new_trace_op.send(:meta)).to eq(tags)
          end

          it 'maintains the same metrics' do
            expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
          end

          it 'maintains the same events' do
            old_events = trace_op.send(:events)
            new_events = new_trace_op.send(:events)

            [
              :span_before_start,
              :span_finished,
              :trace_finished
            ].each do |event|
              expect(new_events.send(event).subscriptions).to eq(old_events.send(event).subscriptions)
            end
          end
        end

        context 'but :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(new_trace_op.parent_span_id).to eq(parent_span_id) }
        end
      end

      context 'is measuring an operation' do
        include_context 'trace attributes'

        before do
          trace_op.measure(
            'grandparent',
            service: 'boo',
            resource: 'far',
            type: 'faz'
          ) do
            trace_op.measure(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ) do |parent|
              @parent = parent
              fork_clone
            end
          end
        end

        it do
          is_expected.to have_attributes(
            agent_sample_rate: agent_sample_rate,
            id: trace_op.id,
            max_length: trace_op.max_length,
            name: be_a_copy_of(name),
            origin: be_a_copy_of(origin),
            parent_span_id: @parent.id,
            rate_limiter_rate: rate_limiter_rate,
            resource: be_a_copy_of(resource),
            rule_sample_rate: rule_sample_rate,
            sample_rate: sample_rate,
            sampled?: sampled,
            sampling_priority: sampling_priority,
            service: be_a_copy_of(service)
          )
        end

        it 'maintains the same tags' do
          expect(new_trace_op.send(:meta)).to eq(tags)
        end

        it 'maintains the same metrics' do
          expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
        end

        context 'and :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(new_trace_op.parent_span_id).to eq(@parent.id) }
        end
      end

      context 'has built a span' do
        include_context 'trace attributes'

        context 'that has not started' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            )
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              agent_sample_rate: agent_sample_rate,
              id: trace_op.id,
              max_length: trace_op.max_length,
              name: be_a_copy_of(name),
              origin: be_a_copy_of(origin),
              parent_span_id: trace_op.parent_span_id,
              rate_limiter_rate: rate_limiter_rate,
              resource: be_a_copy_of(resource),
              rule_sample_rate: rule_sample_rate,
              sample_rate: sample_rate,
              sampled?: sampled,

              sampling_priority: sampling_priority,
              service: be_a_copy_of(service)
            )
          end

          it 'maintains the same tags' do
            expect(new_trace_op.send(:meta)).to eq(tags)
          end

          it 'maintains the same metrics' do
            expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
          end
        end

        context 'that has started' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ).start
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              agent_sample_rate: agent_sample_rate,
              id: trace_op.id,
              max_length: trace_op.max_length,
              name: be_a_copy_of(name),
              origin: be_a_copy_of(origin),
              parent_span_id: parent_span.id,
              rate_limiter_rate: rate_limiter_rate,
              resource: be_a_copy_of(resource),
              rule_sample_rate: rule_sample_rate,
              sample_rate: sample_rate,
              sampled?: sampled,

              sampling_priority: sampling_priority,
              service: be_a_copy_of(service)
            )
          end

          it 'maintains the same tags' do
            expect(new_trace_op.send(:meta)).to eq(tags)
          end

          it 'maintains the same metrics' do
            expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
          end
        end

        context 'that has finished' do
          let(:parent_span) do
            trace_op.build_span(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ).start.finish
          end

          before { parent_span }

          it do
            is_expected.to have_attributes(
              agent_sample_rate: agent_sample_rate,
              id: trace_op.id,
              max_length: trace_op.max_length,
              name: be_a_copy_of(name),
              origin: be_a_copy_of(origin),
              parent_span_id: trace_op.parent_span_id,
              rate_limiter_rate: rate_limiter_rate,
              resource: be_a_copy_of(resource),
              rule_sample_rate: rule_sample_rate,
              sample_rate: sample_rate,
              sampled?: sampled,

              sampling_priority: sampling_priority,
              service: be_a_copy_of(service)
            )
          end

          it 'maintains the same tags' do
            expect(new_trace_op.send(:meta)).to eq(tags)
          end

          it 'maintains the same metrics' do
            expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
          end
        end
      end

      context 'is finished' do
        include_context 'trace attributes'

        before do
          trace_op.measure(
            'grandparent',
            service: 'boo',
            resource: 'far',
            type: 'faz'
          ) do
            trace_op.measure(
              'parent',
              service: 'foo',
              resource: 'bar',
              type: 'baz'
            ) do |parent|
              # Do something
            end
          end
        end

        it do
          is_expected.to have_attributes(
            agent_sample_rate: agent_sample_rate,
            id: trace_op.id,
            max_length: trace_op.max_length,
            name: be_a_copy_of(name),
            origin: be_a_copy_of(origin),
            parent_span_id: trace_op.parent_span_id,
            rate_limiter_rate: rate_limiter_rate,
            resource: be_a_copy_of(resource),
            rule_sample_rate: rule_sample_rate,
            sample_rate: sample_rate,
            sampled?: sampled,

            sampling_priority: sampling_priority,
            service: be_a_copy_of(service)
          )
        end

        it 'maintains the same tags' do
          expect(new_trace_op.send(:meta)).to eq(tags)
        end

        it 'maintains the same metrics' do
          expect(new_trace_op.send(:metrics)).to eq({ 'baz' => 42.0 })
        end

        context 'and :parent_span_id has been defined' do
          let(:options) { { parent_span_id: parent_span_id } }
          let(:parent_span_id) { Datadog::Tracing::Utils.next_id }

          it { expect(new_trace_op.parent_span_id).to be parent_span_id }
        end
      end
    end
  end

  describe 'integration tests' do
    context 'service_entry attributes' do
      context 'when service not given' do
        it do
          trace_op.measure('root') do |_, trace|
            trace.measure('children_1') do
              # sleep(0.01)
            end

            trace.measure('children_2') do
              # sleep(0.01)
            end
          end

          trace_segment = trace_op.flush!

          expect(trace_segment.spans).to include(
            a_span_with(name: 'root', service_entry?: true),
            a_span_with(name: 'children_1', service_entry?: false),
            a_span_with(name: 'children_2', service_entry?: false)
          )
        end
      end

      context 'when service provided at root' do
        it do
          trace_op.measure('root', service: 'service_1') do |_, trace|
            trace.measure('children_1') do
              # sleep(0.01)
            end

            trace.measure('children_2') do
              # sleep(0.01)
            end
          end

          trace_segment = trace_op.flush!

          expect(trace_segment.spans).to include(
            a_span_with(name: 'root', service_entry?: true),
            a_span_with(name: 'children_1', service_entry?: false),
            a_span_with(name: 'children_2', service_entry?: false)
          )
        end
      end

      context 'when service changed' do
        it do
          trace_op.measure('root', service: 'service_1') do |_, trace|
            trace.measure('children_1', service: 'service_2') do
              # sleep(0.01)
            end

            trace.measure('children_2') do
              # sleep(0.01)
            end
          end

          trace_segment = trace_op.flush!

          expect(trace_segment.spans).to include(
            a_span_with(name: 'root', service_entry?: true),
            a_span_with(name: 'children_1', service_entry?: true),
            a_span_with(name: 'children_2', service_entry?: false)
          )
        end
      end

      context 'when service changed within the block' do
        it do
          trace_op.measure('root', service: 'service_1') do |_, trace|
            trace.measure('children_1') do |span|
              span.service = 'service_2'
              # sleep(0.01)
            end

            trace.measure('children_2') do
              # sleep(0.01)
            end
          end

          trace_segment = trace_op.flush!

          expect(trace_segment.spans).to include(
            a_span_with(name: 'root', service_entry?: true),
            a_span_with(name: 'children_1', service_entry?: true),
            a_span_with(name: 'children_2', service_entry?: false)
          )
        end
      end
    end

    context 'for a mock job with fan-out/fan-in behavior' do
      subject(:trace) do
        @thread_traces = Queue.new

        trace_op.measure('job', resource: 'import_job', service: 'job-worker') do |_span, trace|
          trace.measure('load_data', resource: 'imports.csv', service: 'job-worker') do
            trace.measure('read_file', resource: 'imports.csv', service: 'job-worker') do
              sleep(0.01)
            end

            trace.measure('deserialize', resource: 'inventory', service: 'job-worker') do
              sleep(0.01)
            end
          end

          workers = nil
          trace.measure('start_inserts', resource: 'inventory', service: 'job-worker') do
            trace_digest = trace.to_digest

            workers = Array.new(5) do |index|
              Thread.new do
                # Delay start-up slightly
                sleep(0.01)

                thread_trace = described_class.new(
                  id: trace_digest.trace_id,
                  origin: trace_digest.trace_origin,
                  parent_span_id: trace_digest.span_id,
                  sampling_priority: trace_digest.trace_sampling_priority
                )

                @thread_traces.push(thread_trace)

                thread_trace.measure(
                  'db.query',
                  service: 'database',
                  resource: "worker #{index}"
                ) do
                  sleep(0.01)
                end
              end
            end
          end

          trace.measure('wait_inserts', resource: 'inventory', service: 'job-worker') do |wait_span|
            wait_span.set_tag('worker.count', workers.length)
            workers && workers.each { |w| w.alive? && w.join }
          end

          trace.measure('update_log', resource: 'inventory', service: 'job-worker') do
            sleep(0.01)
          end
        end

        trace_op.flush!
      end

      it 'is a well-formed trace' do
        expect { trace }.to_not raise_error

        # Collect traces from threads
        all_thread_traces = []
        all_thread_traces << @thread_traces.pop until @thread_traces.empty?

        # Collect spans from original trace + threads
        all_spans = (trace.spans + all_thread_traces.collect { |t| t.flush!.spans }).flatten
        expect(all_spans).to have(12).items

        job_span = all_spans.find { |s| s.name == 'job' }
        load_data_span = all_spans.find { |s| s.name == 'load_data' }
        read_file_span = all_spans.find { |s| s.name == 'read_file' }
        deserialize_span = all_spans.find { |s| s.name == 'deserialize' }
        start_inserts_span = all_spans.find { |s| s.name == 'start_inserts' }
        db_query_spans = all_spans.select { |s| s.name == 'db.query' }
        wait_insert_span = all_spans.find { |s| s.name == 'wait_inserts' }
        update_log_span = all_spans.find { |s| s.name == 'update_log' }

        trace_id = job_span.trace_id

        expect(job_span).to have_attributes(
          trace_id: (a_value > 0),
          id: (a_value > 0),
          parent_id: 0,
          name: 'job',
          resource: 'import_job',
          service: 'job-worker'
        )
        expect(job_span.__send__(:service_entry?)).to be true

        expect(load_data_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'load_data',
          resource: 'imports.csv',
          service: 'job-worker'
        )
        expect(load_data_span.__send__(:service_entry?)).to be false

        expect(read_file_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: load_data_span.id,
          name: 'read_file',
          resource: 'imports.csv',
          service: 'job-worker'
        )
        expect(read_file_span.__send__(:service_entry?)).to be false

        expect(deserialize_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: load_data_span.id,
          name: 'deserialize',
          resource: 'inventory',
          service: 'job-worker'
        )
        expect(deserialize_span.__send__(:service_entry?)).to be false

        expect(start_inserts_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'start_inserts',
          resource: 'inventory',
          service: 'job-worker'
        )
        expect(start_inserts_span.__send__(:service_entry?)).to be false

        expect(db_query_spans).to all(
          have_attributes(
            trace_id: trace_id,
            id: (a_value > 0),
            parent_id: start_inserts_span.id,
            name: 'db.query',
            resource: /worker \d+/,
            service: 'database'
          )
        )
        expect(db_query_spans.map { |s| s.__send__(:service_entry?) }).to all(be true)

        expect(wait_insert_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'wait_inserts',
          resource: 'inventory',
          service: 'job-worker'
        )
        expect(wait_insert_span.get_tag('worker.count')).to eq(5.0)
        expect(wait_insert_span.__send__(:service_entry?)).to be false

        expect(update_log_span).to have_attributes(
          trace_id: trace_id,
          id: (a_value > 0),
          parent_id: job_span.id,
          name: 'update_log',
          resource: 'inventory',
          service: 'job-worker'
        )
        expect(update_log_span.__send__(:service_entry?)).to be false
      end
    end
  end
end
