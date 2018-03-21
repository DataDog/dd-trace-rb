require 'spec_helper'
require 'ddtrace'

require 'active_support/notifications'
require 'ddtrace/contrib/active_support/notifications/subscription'

RSpec.describe Datadog::Contrib::ActiveSupport::Notifications::Subscription do
  describe 'instance' do
    subject(:subscription) { described_class.new(tracer, span_name, options, &block) }
    let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
    let(:span_name) { double('span_name') }
    let(:options) { double('options') }
    let(:block) do
      Proc.new do |span, name, id, payload|
        spy.call(span, name, id, payload)
      end
    end
    let(:spy) { double('spy') }

    describe 'behavior' do
      describe '#start' do
        subject(:result) { subscription.start(name, id, payload) }
        let(:name) { double('name') }
        let(:id) { double('id') }
        let(:payload) { double('payload') }

        let(:span) { instance_double(Datadog::Span) }

        it do
          expect(tracer).to receive(:trace).with(span_name, options).and_return(span)
          is_expected.to be(span)
        end
      end

      describe '#finish' do
        subject(:result) { subscription.finish(name, id, payload) }
        let(:name) { double('name') }
        let(:id) { double('id') }
        let(:payload) { double('payload') }

        let(:span) { instance_double(Datadog::Span) }

        it do
          expect(tracer).to receive(:active_span).and_return(span).ordered
          expect(spy).to receive(:call).with(span, name, id, payload).ordered
          expect(span).to receive(:finish).and_return(span).ordered
          is_expected.to be(span)
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
