require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'

require 'active_support/notifications'
require 'ddtrace/contrib/active_support/notifications/subscription'

RSpec.describe Datadog::Contrib::ActiveSupport::Notifications::Subscription do
  describe 'instance' do
    subject(:subscription) { described_class.new(tracer, span_name, options, &block) }
    let(:span_name) { double('span_name') }
    let(:options) { {} }
    let(:payload) { {} }
    let(:block) do
      proc do |span, name, id, payload|
        spy.call(span, name, id, payload)
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

        let(:span) { instance_double(Datadog::Span) }

        it do
          expect(tracer).to receive(:trace).with(span_name, options).and_return(span).ordered
          expect(span).to receive(:start_time=).with(start).and_return(span).ordered
          expect(spy).to receive(:call).with(span, name, id, payload).ordered
          expect(span).to receive(:finish).with(finish).and_return(span).ordered
          is_expected.to be(span)
        end

        context 'when block raises an error' do
          let(:block) do
            proc do |_span, _name, _id, _payload|
              raise ArgumentError, 'Fail!'
            end
          end

          around(:each) { |example| without_errors { example.run } }

          it 'finishes tracing anyways' do
            expect(tracer).to receive(:trace).with(span_name, options).and_return(span).ordered
            expect(span).to receive(:start_time=).with(start).and_return(span).ordered
            expect(span).to receive(:finish).with(finish).and_return(span).ordered
            is_expected.to be(span)
          end
        end
      end

      describe '#start' do
        subject(:result) { subscription.start(name, id, payload) }
        let(:name) { double('name') }
        let(:id) { double('id') }
        let(:span) { double('span') }

        it do
          expect(tracer).to receive(:trace).with(span_name, options).and_return(span)
          is_expected.to be(span)
        end

        it 'sets the parent span' do
          parent = tracer.trace('parent_span')
          expect(subject.parent_id).to eq parent.span_id
        end

        it 'sets span in payload' do
          expect { subject }.to change { payload[:datadog_span] }.to be_instance_of(Datadog::Span)
        end
      end

      describe '#finish' do
        subject(:result) { subscription.finish(name, id, payload) }
        let(:name) { double('name') }
        let(:id) { double('id') }

        let(:span) { instance_double(Datadog::Span) }
        let(:payload) { { datadog_span: span } }

        it do
          expect(spy).to receive(:call).with(span, name, id, payload).ordered
          expect(span).to receive(:finish).and_return(span).ordered
          is_expected.to be(span)
        end
      end

      describe '#before_trace' do
        context 'given a block' do
          let(:callback_block) { proc { callback_spy.call } }
          let(:callback_spy) { double('callback spy') }
          before(:each) { subscription.before_trace(&callback_block) }

          shared_examples_for 'a before_trace callback' do
            context 'on #start' do
              it do
                expect(callback_spy).to receive(:call).ordered
                expect(tracer).to receive(:trace).ordered
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
            around(:each) { |example| without_errors { example.run } }
            it_behaves_like 'a before_trace callback'
          end
        end
      end

      describe '#after_trace' do
        context 'given a block' do
          let(:callback_block) { proc { callback_spy.call } }
          let(:callback_spy) { double('callback spy') }
          before(:each) { subscription.after_trace(&callback_block) }

          shared_examples_for 'an after_trace callback' do
            context 'on #finish' do
              let(:span) { instance_double(Datadog::Span) }
              let(:payload) { { datadog_span: span } }

              it do
                expect(spy).to receive(:call).ordered
                expect(span).to receive(:finish).ordered
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
            around(:each) { |example| without_errors { example.run } }
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
          before(:each) do
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
          before(:each) do
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
          before(:each) do
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
