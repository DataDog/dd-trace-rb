require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'

require 'active_support/notifications'
require 'datadog/tracing/contrib/active_support/notifications/event'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Notifications::Event do
  describe 'implemented' do
    subject(:test_class) do
      test_event_name = event_name
      test_span_name = span_name

      Class.new.tap do |klass|
        klass.include(described_class)
        klass.send(:define_singleton_method, :event_name) { test_event_name }
        klass.send(:define_singleton_method, :span_name) { test_span_name }
        klass.send(:define_singleton_method, :process, &process_block)
      end
    end

    let(:event_name) { double('event_name') }
    let(:span_name) { double('span_name') }
    let(:process_block) { proc { spy.call } }
    let(:spy) { double(:spy) }

    describe 'class' do
      describe 'behavior' do
        describe '#subscribe!' do
          subject(:result) { test_class.subscribe! }

          it do
            expect(ActiveSupport::Notifications).to receive(:subscribe)
              .with(event_name, be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription))
            is_expected.to be true
          end

          context 'is called a second time' do
            before do
              allow(ActiveSupport::Notifications).to receive(:subscribe)
                .with(event_name, be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription))
              test_class.subscribe!
            end

            it do
              expect(ActiveSupport::Notifications).to_not receive(:subscribe)
              is_expected.to be true
            end
          end
        end

        describe '#subscribe' do
          before do
            expect(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription).to receive(:new)
              .with(test_class.span_name, test_class.span_options)
              .and_call_original
          end

          context 'when given no pattern' do
            subject(:subscription) { test_class.subscribe }

            before do
              expect_any_instance_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription)
                .to receive(:subscribe)
                .with(event_name)
            end

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription) }
            it { expect(test_class.subscriptions).to contain_exactly(subscription) }
          end

          context 'when given a pattern' do
            subject(:subscription) { test_class.subscribe(pattern) }

            let(:pattern) { double('pattern') }

            before do
              expect_any_instance_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription)
                .to receive(:subscribe)
                .with(pattern)
            end

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription) }
            it { expect(test_class.subscriptions).to contain_exactly(subscription) }
          end
        end

        describe '#subscription' do
          context 'when given no options' do
            subject(:subscription) { test_class.subscription }

            before do
              expect(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription).to receive(:new)
                .with(test_class.span_name, test_class.span_options)
                .and_call_original
            end

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription) }
            it { expect(test_class.subscriptions).to contain_exactly(subscription) }
          end

          context 'when given options' do
            subject(:subscription) { test_class.subscription(span_name, options) }

            let(:span_name) { double('span name') }
            let(:options) { double('options') }

            before do
              expect(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription).to receive(:new)
                .with(span_name, options)
                .and_call_original
            end

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription) }
            it { expect(test_class.subscriptions).to contain_exactly(subscription) }
          end
        end
      end
    end
  end
end
