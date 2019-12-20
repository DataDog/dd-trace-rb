require 'spec_helper'

require 'ddtrace'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/contrib/tracer_examples'

require 'rails'
require 'active_support/core_ext/hash/indifferent_access'

begin
  require 'action_cable'
rescue LoadError
  puts 'ActionCable not supported in Rails < 5.0'
end

RSpec.describe 'ActionCable patcher' do
  before { skip('ActionCable not supported') unless Datadog::Contrib::ActionCable::Integration.compatible? }

  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before do
    Datadog.configure do |c|
      c.use :action_cable, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:action_cable].reset_configuration!
    example.run
    Datadog.registry[:action_cable].reset_configuration!
  end

  let(:all_spans) { tracer.writer.spans(:keep) }

  let(:span) do
    expect(all_spans).to have(1).item
    all_spans.find { |s| s.service == 'action_cable' }
  end

  context 'with server' do
    let(:channel) { 'chat_room' }
    let(:message) { 'Hello Internet!' }

    let(:server) do
      ActionCable::Server::Base.new.tap do |s|
        s.config.cable = { adapter: 'inline' }.with_indifferent_access
        s.config.logger = Logger.new(nil)
      end
    end

    context 'on broadcast' do
      subject(:broadcast) { server.broadcast(channel, message) }

      it 'traces broadcast event' do
        broadcast

        expect(span.service).to eq('action_cable')
        expect(span.name).to eq('action_cable.broadcast')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('action_cable.broadcast')
        expect(span.get_tag('action_cable.channel')).to eq(channel)
        expect(span.get_tag('action_cable.broadcast.coder')).to eq('ActiveSupport::JSON')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before { ActiveSupport::Notifications.instrument(Datadog::Contrib::ActionCable::Events::Broadcast::EVENT_NAME) }
        let(:analytics_enabled_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end

  context 'with channel' do
    let(:channel_class) do
      stub_const('ChatChannel', Class.new(ActionCable::Channel::Base) do
        def foo(_data); end
      end)
    end

    let(:channel_instance) { channel_class.new(connection, '{id: 1}', id: 1) }
    let(:connection) { double('connection', logger: Logger.new(nil), transmit: nil, identifiers: []) }

    context 'on perform action' do
      subject(:perform) { channel_instance.perform_action(data) }

      let(:data) { { 'action' => 'foo', 'extra' => 'data' } }

      it 'traces perform action event' do
        perform

        expect(span.service).to eq('action_cable')
        expect(span.name).to eq('action_cable.action')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel#foo')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag('action_cable.action')).to eq('foo')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before { ActiveSupport::Notifications.instrument(Datadog::Contrib::ActionCable::Events::PerformAction::EVENT_NAME) }
        let(:analytics_enabled_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      context 'with an unfinished trace' do
        include_context 'an unfinished trace'

        let(:event_name) { 'Datadog::Contrib::ActionCable::Events::PerformAction' }

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
        stub_const('ChatChannel', Class.new(ActionCable::Channel::Base) do
          def foo(data)
            transmit({ mock: 'data' }, via: 'streamed from chat_channel')
          end
        end)
      end

      let(:span) { all_spans.last } # Skip 'perform_action' span

      it 'traces transmit event' do
        perform

        expect(all_spans).to have(2).items
        expect(span.service).to eq('action_cable')
        expect(span.name).to eq('action_cable.transmit')
        expect(span.span_type).to eq('web')
        expect(span.resource).to eq('ChatChannel')
        expect(span.get_tag('action_cable.channel_class')).to eq('ChatChannel')
        expect(span.get_tag('action_cable.transmit.via')).to eq('streamed from chat_channel')
        expect(span).to_not have_error
      end

      it_behaves_like 'analytics for integration' do
        before { ActiveSupport::Notifications.instrument(Datadog::Contrib::ActionCable::Events::Transmit::EVENT_NAME) }
        let(:analytics_enabled_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::ActionCable::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end
    end
  end
end
