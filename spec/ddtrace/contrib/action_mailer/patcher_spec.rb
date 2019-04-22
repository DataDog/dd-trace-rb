require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'rails'
require 'active_support'
require 'ddtrace'

RSpec.describe 'ActionMailer patcher' do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  def all_spans
    tracer.writer.spans(:keep)
  end

  before(:each) do
    if Datadog::Contrib::ActionMailer::Integration.compatible?
      Datadog.configure do |c|
        c.use :action_mailer, configuration_options
      end
    else
      skip
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:action_mailer].reset_configuration!
    example.run
    Datadog.registry[:action_mailer].reset_configuration!
  end

  describe 'for single process.action_mailer process' do
    let(:mailer) { 'UserMailer' }
    let(:action) { 'example_welcome_email' }
    let(:args) do
      []
    end

    let(:span) do
      all_spans.select { |s| s.name == Datadog::Contrib::ActionMailer::Ext::SPAN_PROCESS }.first
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a span' do
        ActiveSupport::Notifications.instrument('process.action_mailer', payload)

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('action_mailer')
          expect(span.name).to eq('process.action_mailer')
          expect(span.resource).to eq(mailer)
          expect(span.get_tag('action_mailer.action')).to eq(action)
          expect(span.get_tag('action_mailer.mailer')).to eq(mailer)
          expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    context 'that raises an error' do
      let(:error_class) { Class.new(StandardError) }

      it 'is expected to send a span' do
        # Emulate failure
        begin
          ActiveSupport::Notifications.instrument('process.action_mailer', payload) do
            raise error_class
          end
        rescue error_class
          nil
        end

        span.tap do |span|
          expect(span).to_not be nil
          expect(span.service).to eq('action_mailer')
          expect(span.name).to eq('process.action_mailer')
          expect(span.resource).to eq(mailer)
          expect(span.get_tag('action_mailer.process')).to eq(action)
          expect(span.get_tag('action_mailer.mailer')).to eq(mailer)
          expect(span.status).to eq(Datadog::Ext::Errors::STATUS)
        end
      end
    end

    it_behaves_like 'analytics for integration' do
      before { ActiveSupport::Notifications.instrument('process.action_mailer', payload) }
      let(:analytics_enabled_var) { Datadog::Contrib::ActionMailer::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::ActionMailer::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end
  end
end