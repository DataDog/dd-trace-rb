require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/action_cable/integration'
require 'rails'
require 'active_support'
require 'ddtrace'

RSpec.describe 'ActionCable patcher' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    if Datadog::Contrib::ActionCable::Integration.compatible?
      Datadog.configure do |c|
        c.use :action_cable, configuration_options
      end
    else
      skip
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:action_cable].reset_configuration!
    example.run
    Datadog.registry[:action_cable].reset_configuration!
  end

  describe 'for single perform_action process' do
    let(:channel) { 'ChatChannel' }
    let(:action) { 'shout' }
    let(:payload) do
      {
        channel_class: channel,
        action: action
      }
    end

    let(:span) do
      all_spans.select { |s| s.name == Datadog::Contrib::ActionCable::Ext::SPAN_PERFORM_ACTION }.first
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('perform_action.action_cable', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('action_cable')
          expect(span.name).to eq('perform_action.action_cable')
          expect(span.resource).to eq(channel)
          expect(span.get_tag('action_cable.perform_action')).to eq(action)
          expect(span.get_tag('action_cable.channel_class')).to eq(channel)
          expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('perform_action.action_cable', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('action_cable')
          expect(span.name).to eq('perform_action.action_cable')
          expect(span.resource).to eq(channel)
          expect(span.get_tag('action_cable.perform_action')).to eq(action)
          expect(span.get_tag('action_cable.channel_class')).to eq(channel)
          expect(span.status).to eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('perform_action.action_cable', payload) }
      let(:analytics_enabled_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end
end
