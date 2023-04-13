require 'logger'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/action_cable/ext'
require 'datadog/tracing/contrib/action_cable/events/broadcast'

require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'spec/datadog/tracing/contrib/rails/support/deprecation'

begin
  require 'action_cable'
rescue LoadError
  puts 'ActionCable not supported in Rails < 5.0'
end

RSpec.describe 'ActionCable patcher' do
  before { skip('ActionCable not supported') unless Datadog::Tracing::Contrib::ActionCable::Integration.compatible? }

  let(:configuration_options) { {} }
  let(:span) do
    expect(spans).to have(1).item
    spans.first
  end

  before do
    Datadog.configure do |c|
      c.tracing.instrument :action_cable, configuration_options
    end

    raise_on_rails_deprecation!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:action_cable].reset_configuration!
    example.run
    Datadog.registry[:action_cable].reset_configuration!
  end

  context 'with server' do
    let(:channel) { 'chat_room' }
    let(:message) { 'Hello Internet!' }

    let(:server) do
      ActionCable::Server::Base.new.tap do |s|
        s.config.cable = { adapter: 'inline' }.with_indifferent_access
        s.config.logger = Logger.new($stdout)
      end
    end

    context 'on broadcast' do
      subject(:broadcast) { server.broadcast(channel, message) }

      it 'traces broadcast event' do
        broadcast

        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('action_cable.broadcast')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('action_cable.broadcast')
        expect(span.get_tag('action_cable.channel')).to eq(channel)
        expect(span.get_tag('action_cable.broadcast.coder')).to eq('ActiveSupport::JSON')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_cable')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('broadcast')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::Broadcast::EVENT_NAME
          )
        end

        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::Broadcast::EVENT_NAME
          )
        end
      end
    end
  end

  context 'with channel' do
    let(:channel_class) do
      stub_const(
        'ChatChannel',
        Class.new(ActionCable::Channel::Base) do
          def subscribed; end

          def unsubscribed; end

          def foo(_data); end
        end
      )
    end

    let(:channel_instance) { channel_class.new(connection, '{id: 1}', id: 1) }
    let(:connection) { double('connection', logger: Logger.new($stdout), transmit: nil, identifiers: []) }

    context 'on subscribe' do
      include_context 'Rails test application'

      subject(:subscribe) { channel_instance.subscribe_to_channel }

      before { app }

      it 'traces the subscribe hook' do
        subscribe

        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('action_cable.subscribe')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel#subscribe')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_cable')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('subscribe')
        expect(span).to_not have_error
      end
    end

    context 'on unsubscribe' do
      include_context 'Rails test application'

      subject(:unsubscribe) { channel_instance.unsubscribe_from_channel }

      before { app }

      it 'traces the unsubscribe hook' do
        unsubscribe

        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('action_cable.unsubscribe')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel#unsubscribe')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_cable')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('unsubscribe')
        expect(span).to_not have_error
      end
    end

    context 'on perform action' do
      subject(:perform) { channel_instance.perform_action(data) }

      let(:data) { { 'action' => 'foo', 'extra' => 'data' } }

      it 'traces perform action event' do
        perform

        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('action_cable.action')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel#foo')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag('action_cable.action')).to eq('foo')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_cable')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('action')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::PerformAction::EVENT_NAME
          )
        end

        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::PerformAction::EVENT_NAME
          )
        end
      end

      context 'with a leaking context' do
        let!(:leaky_span) { tracer.trace('unfinished_span') }

        it 'traces transmit event' do
          perform
          expect(span.name).to eq('action_cable.action')
        end
      end
    end

    context 'on transmit' do
      subject(:perform) { channel_instance.perform_action(data) }

      let(:data) { { 'action' => 'foo', 'extra' => 'data' } }
      let(:channel_class) do
        stub_const(
          'ChatChannel',
          Class.new(ActionCable::Channel::Base) do
            def foo(_data)
              transmit({ mock: 'data' }, via: 'streamed from chat_channel')
            end
          end
        )
      end

      let(:span) { spans.last } # Skip 'perform_action' span

      it 'traces transmit event' do
        perform

        expect(spans).to have(2).items
        expect(span.service).to eq(tracer.default_service)
        expect(span.name).to eq('action_cable.transmit')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag('action_cable.transmit.via')).to eq('streamed from chat_channel')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('action_cable')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('transmit')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::Transmit::EVENT_NAME
          )
        end

        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', false do
        before do
          ActiveSupport::Notifications.instrument(
            Datadog::Tracing::Contrib::ActionCable::Events::Transmit::EVENT_NAME
          )
        end
      end
    end
  end
end
