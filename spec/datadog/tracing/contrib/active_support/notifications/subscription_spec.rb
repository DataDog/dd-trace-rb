require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog'

require 'active_support/notifications'
require 'datadog/tracing/contrib/active_support/notifications/subscription'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription do
  describe 'instance' do
    subject(:subscription) do
      described_class.new(span_name, options, on_start: on_start, on_finish: on_finish, trace: trace)
    end

    let(:span_name) { double('span_name') }
    let(:options) { { resource: 'dummy_resource' } }
    let(:on_start) { proc { |span_op, name, id, payload| on_start_spy.call(span_op, name, id, payload) } }
    let(:on_finish) { proc { |span_op, name, id, payload| on_finish_spy.call(span_op, name, id, payload) } }
    let(:trace) { proc { |_name, _payload| true } }
    let(:payload) { {} }

    let(:on_start_spy) { double('on_start_spy') }
    let(:on_finish_spy) { double('on_finish_spy') }

    describe 'behavior' do
      describe '#start' do
        subject(:result) { subscription.start(name, id, payload) }

        let(:name) { double('name') }
        let(:id) { double('id') }
        let(:span_op) { double('span_op') }

        before { allow(on_start_spy).to receive(:call) }

        it 'returns the span operation' do
          expect(on_start_spy).to receive(:call).with(span_op, name, id, payload)
          expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op)
          is_expected.to be(span_op)
          expect(payload[:datadog_span]).to eq(span_op)
        end

        it 'sets the parent span operation' do
          parent = Datadog::Tracing.trace('parent_span_operation')
          expect(subject.parent_id).to eq parent.id
        end

        it 'sets span operation in payload' do
          expect(on_start_spy).to receive(:call).with(span_op, name, id, payload)
          expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op)
          expect { subject }.to change { payload[:datadog_span] }.to be(span_op)
        end

        context 'with trace? returning false' do
          let(:trace) { proc { |_name, _payload| false } }

          it 'does not start a span operation nor call the callback' do
            expect(Datadog::Tracing).not_to receive(:trace)
            expect(on_start_spy).to_not receive(:call)
            is_expected.to be_nil
            expect(payload[:datadog_span]).to be_nil
          end
        end
      end

      describe '#finish' do
        subject(:result) { subscription.finish(name, id, payload) }

        let(:name) { double('name') }
        let(:id) { double('id') }

        let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }
        let(:payload) { { datadog_span: span_op } }

        it do
          expect(on_finish_spy).to receive(:call).with(span_op, name, id, payload).ordered
          expect(span_op).to receive(:finish).and_return(span_op).ordered
          is_expected.to be(span_op)
        end

        context 'without a span started' do
          let(:payload) { {} }

          it 'does not call the callback' do
            expect(on_finish_spy).to_not receive(:call)
            is_expected.to be_nil
          end
        end
      end

      describe '#before_trace' do
        context 'given a block' do
          let(:callback_block) { proc { callback_spy.call } }
          let(:callback_spy) { double('callback spy') }

          before { subscription.before_trace(&callback_block) }

          shared_examples_for 'a before_trace callback' do
            context 'on #start' do
              it do
                allow(on_start_spy).to receive(:call)
                expect(callback_spy).to receive(:call).ordered
                expect(Datadog::Tracing).to receive(:trace).ordered
                subscription.start(double('name'), double('id'), payload)
              end
            end
          end

          context 'that doesn\'t raise an error' do
            let(:callback_block) { proc { callback_spy.call } }

            it_behaves_like 'a before_trace callback'
          end

          context 'that raises an error' do
            let(:callback_block) do
              proc do
                callback_spy.call
                raise ArgumentError, 'Fail!'
              end
            end

            around { |example| without_errors { example.run } }

            it_behaves_like 'a before_trace callback'
          end

          context 'with trace? returning false' do
            let(:trace) { proc { |_name, _payload| false } }

            it 'does not call the callback' do
              expect(callback_spy).not_to receive(:call)
              subscription.start(double('name'), double('id'), payload)
            end
          end
        end
      end

      describe '#after_trace' do
        context 'given a block' do
          let(:callback_block) { proc { callback_spy.call } }
          let(:callback_spy) { double('callback spy') }

          before { subscription.after_trace(&callback_block) }

          shared_examples_for 'an after_trace callback' do
            context 'on #finish' do
              let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }
              let(:payload) { { datadog_span: span_op } }

              it do
                allow(on_finish_spy).to receive(:call)
                expect(span_op).to receive(:finish).ordered
                expect(callback_spy).to receive(:call).ordered
                subscription.finish(double('name'), double('id'), payload)
              end
            end
          end

          context 'that doesn\'t raise an error' do
            let(:callback_block) { proc { callback_spy.call } }

            it_behaves_like 'an after_trace callback'
          end

          context 'that raises an error' do
            let(:callback_block) do
              proc do
                callback_spy.call
                raise ArgumentError, 'Fail!'
              end
            end

            around { |example| without_errors { example.run } }

            it_behaves_like 'an after_trace callback'
          end

          context 'with trace? returning false' do
            let(:trace) { proc { |_name, _payload| false } }

            it 'does not call the callback' do
              expect(callback_spy).not_to receive(:call)
              subscription.finish(double('name'), double('id'), payload)
            end
          end
        end
      end

      describe '#subscribe' do
        subject(:result) { subscription.subscribe(pattern) }

        let(:pattern) { double('pattern') }

        let(:active_support_subscriber) { double('ActiveSupport subscriber') }

        context 'when not already subscribed to the pattern' do
          it do
            expect(ActiveSupport::Notifications).to receive(:subscribe)
              .with(pattern, subscription)
              .and_return(active_support_subscriber)

            is_expected.to be true
            expect(subscription.send(:subscribers)).to include(pattern => active_support_subscriber)
          end
        end

        context 'when already subscribed to the pattern' do
          before do
            allow(ActiveSupport::Notifications).to receive(:subscribe)
              .with(pattern, subscription)
              .and_return(active_support_subscriber)

            subscription.subscribe(pattern)
          end

          it { is_expected.to be false }
        end
      end

      describe '#unsubscribe' do
        subject(:result) { subscription.unsubscribe(pattern) }

        let(:pattern) { double('pattern') }

        let(:active_support_subscriber) { double('ActiveSupport subscriber') }

        context 'when not already subscribed to the pattern' do
          it { is_expected.to be false }
        end

        context 'when already subscribed to the pattern' do
          before do
            allow(ActiveSupport::Notifications).to receive(:subscribe)
              .with(pattern, subscription)
              .and_return(active_support_subscriber)

            subscription.subscribe(pattern)
          end

          it do
            expect(subscription.send(:subscribers)).to have(1).items
            expect(ActiveSupport::Notifications).to receive(:unsubscribe)
              .with(active_support_subscriber)

            is_expected.to be true
            expect(subscription.send(:subscribers)).to be_empty
          end
        end
      end

      describe '#unsubscribe_all' do
        subject(:result) { subscription.unsubscribe_all }

        let(:active_support_subscriber) { double('ActiveSupport subscriber') }

        context 'when not already subscribed to the pattern' do
          it { is_expected.to be false }
        end

        context 'when already subscribed to the pattern' do
          before do
            allow(ActiveSupport::Notifications).to receive(:subscribe)
              .with(kind_of(String), subscription)
              .and_return(active_support_subscriber)

            subscription.subscribe('pattern 1')
            subscription.subscribe('pattern 2')
          end

          it do
            expect(subscription.send(:subscribers)).to have(2).items
            expect(ActiveSupport::Notifications).to receive(:unsubscribe)
              .with(active_support_subscriber)
              .twice

            is_expected.to be true
            expect(subscription.send(:subscribers)).to be_empty
          end
        end
      end
    end
  end
end
