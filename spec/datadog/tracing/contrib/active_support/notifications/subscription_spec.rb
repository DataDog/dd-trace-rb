require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'

require 'active_support/notifications'
require 'datadog/tracing/contrib/active_support/notifications/subscription'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription do
  describe 'instance' do
    subject(:subscription) { described_class.new(span_name, options, &block) }

    let(:span_name) { double('span_name') }
    let(:options) { { resource: 'dummy_resource' } }
    let(:payload) { {} }
    let(:block) do
      proc do |span_op, name, id, payload|
        spy.call(span_op, name, id, payload)
      end
    end
    let(:spy) { double('spy') }

    describe 'behavior' do
      describe '#call' do
        subject(:result) { subscription.call(name, start, finish, id, payload) }

        let(:name) { double('name') }
        let(:start) { double('start') }
        let(:finish) { double('finish') }
        let(:id) { double('id') }
        let(:payload) { {} }

        let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }

        it do
          expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op).ordered
          expect(span_op).to receive(:start).with(start).and_return(span_op).ordered
          expect(spy).to receive(:call).with(span_op, name, id, payload).ordered
          expect(span_op).to receive(:finish).with(finish).and_return(span_op).ordered
          is_expected.to be(span_op)
        end

        context 'when block raises an error' do
          let(:block) do
            proc do |_span_op, _name, _id, _payload|
              raise ArgumentError, 'Fail!'
            end
          end

          around { |example| without_errors { example.run } }

          it 'finishes tracing anyways' do
            expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op).ordered
            expect(span_op).to receive(:start).with(start).and_return(span_op).ordered
            expect(span_op).to receive(:finish).with(finish).and_return(span_op).ordered
            is_expected.to be(span_op)
          end
        end
      end

      describe '#start' do
        subject(:result) { subscription.start(name, id, payload) }

        let(:name) { double('name') }
        let(:id) { double('id') }
        let(:span_op) { double('span_op') }

        it 'returns the span operation' do
          expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op)
          is_expected.to be(span_op)
        end

        it 'sets the parent span operation' do
          parent = Datadog::Tracing.trace('parent_span_operation')
          expect(subject.parent_id).to eq parent.span_id
        end

        it 'sets span operation in payload' do
          expect(Datadog::Tracing).to receive(:trace).with(span_name, **options).and_return(span_op)
          expect { subject }.to change { payload[:datadog_span] }.to be(span_op)
        end
      end

      describe '#finish' do
        subject(:result) { subscription.finish(name, id, payload) }

        let(:name) { double('name') }
        let(:id) { double('id') }

        let(:span_op) { instance_double(Datadog::Tracing::SpanOperation) }
        let(:payload) { { datadog_span: span_op } }

        it do
          expect(spy).to receive(:call).with(span_op, name, id, payload).ordered
          expect(span_op).to receive(:finish).and_return(span_op).ordered
          is_expected.to be(span_op)
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
                expect(spy).to receive(:call).ordered
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
