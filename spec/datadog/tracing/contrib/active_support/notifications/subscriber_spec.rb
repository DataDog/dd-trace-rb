require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'

require 'datadog/tracing/contrib/active_support/notifications/subscriber'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscriber do
  describe 'implemented' do
    subject(:test_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    describe 'class' do
      describe 'behavior' do
        describe '#subscriptions' do
          subject(:subscriptions) { test_class.subscriptions }

          context 'when no subscriptions have been created' do
            it { is_expected.to be_empty }
          end

          context 'when a subscription has been created' do
            it do
              subscription = test_class.send(
                :subscription,
                double('span name'),
                double('options'),
                &proc {}
              )

              is_expected.to contain_exactly(subscription)
            end
          end
        end

        describe '#subscribed?' do
          subject(:subscribed) { test_class.subscribed? }

          context 'when #subscribe! hasn\'t been called' do
            it { is_expected.to be false }
          end

          context 'after #subscribe! has been called' do
            before do
              test_class.send(:on_subscribe, &proc {})
              test_class.send(:subscribe!)
            end

            it { is_expected.to be true }
          end
        end

        context 'that is protected' do
          describe '#subscribe!' do
            subject(:result) { test_class.send(:subscribe!) }

            context 'when #on_subscribe' do
              context 'is defined' do
                let(:on_subscribe_block) { proc { spy.call } }
                let(:spy) { double(:spy) }

                before { test_class.send(:on_subscribe, &on_subscribe_block) }

                it do
                  expect(spy).to receive(:call)
                  is_expected.to be true
                end

                context 'but has already been called once' do
                  before do
                    allow(spy).to receive(:call)
                    test_class.send(:subscribe!)
                  end

                  it do
                    expect(spy).to_not receive(:call)
                    is_expected.to be true
                  end
                end
              end

              context 'is not defined' do
                it { is_expected.to be false }
              end
            end
          end

          describe '#subscribe' do
            subject(:subscription) { test_class.send(:subscribe, pattern, span_name, options, &block) }

            let(:pattern) { double('pattern') }
            let(:span_name) { double('span name') }
            let(:options) { double('options') }
            let(:block) { proc {} }

            before do
              expect(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription).to receive(:new)
                .with(span_name, options)
                .and_call_original

              expect_any_instance_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription)
                .to receive(:subscribe)
                .with(pattern)
            end

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::ActiveSupport::Notifications::Subscription) }
            it { expect(test_class.subscriptions).to contain_exactly(subscription) }
          end

          describe '#subscription' do
            subject(:subscription) { test_class.send(:subscription, span_name, options, &block) }

            let(:span_name) { double('span name') }
            let(:options) { double('options') }
            let(:block) { proc {} }

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
