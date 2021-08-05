# typed: ignore

require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'rails'
require 'active_support'
require 'spec/ddtrace/contrib/action_mailer/helpers'
require 'ddtrace/contrib/action_mailer/integration'
require 'ddtrace'

begin
  require 'action_mailer'
rescue LoadError
  puts 'ActionCable not supported in Rails < 5.0'
end

RSpec.describe 'ActionMailer patcher' do
  include_context 'ActionMailer helpers'

  let(:configuration_options) { {} }

  before do
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
    let(:action) { 'test_mail' }
    let(:args) do
      []
    end

    let(:span) do
      spans.find { |s| s.name == Datadog::Contrib::ActionMailer::Ext::SPAN_PROCESS }
    end

    let(:deliver_span) do
      spans.find { |s| s.name == Datadog::Contrib::ActionMailer::Ext::SPAN_DELIVER }
    end

    before do
      UserMailer.test_mail(1).deliver_now
    end

    context 'that doesn\'t raise an error' do
      it 'is expected to send a process span' do
        expect(span).to_not be nil
        expect(span.service).to eq('action_mailer')
        expect(span.name).to eq('action_mailer.process')
        expect(span.resource).to eq(mailer)
        expect(span.get_tag('action_mailer.action')).to eq(action)
        expect(span.get_tag('action_mailer.mailer')).to eq(mailer)
        expect(span.span_type).to eq('template')
        expect(span.status).to_not eq(Datadog::Ext::Errors::STATUS)
      end

      it 'is expected to send a deliver span' do
        expect(deliver_span).to_not be nil
        expect(deliver_span.service).to eq('action_mailer')
        expect(deliver_span.name).to eq('action_mailer.deliver')
        expect(deliver_span.resource).to eq(mailer)
        expect(deliver_span.get_tag('action_mailer.mailer')).to eq(mailer)
        expect(deliver_span.span_type).to eq('worker')
        expect(deliver_span.get_tag('action_mailer.message_id')).to_not be nil
        expect(deliver_span.status).to_not eq(Datadog::Ext::Errors::STATUS)
      end

      it_behaves_like 'analytics for integration' do
        before { UserMailer.test_mail(1).deliver_now }
        let(:analytics_enabled_var) { Datadog::Contrib::ActionMailer::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Contrib::ActionMailer::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like 'measured span for integration', true
    end
  end
end
