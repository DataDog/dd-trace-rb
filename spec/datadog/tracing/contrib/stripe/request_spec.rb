require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'stripe'

RSpec.describe Datadog::Tracing::Contrib::Stripe::Request do
  before do
    WebMock.enable!
    WebMock.disable_net_connect!

    Stripe.api_key = 'sk_test_123'

    Datadog.configure do |c|
      c.tracing.instrument :stripe
    end

    stub_request(:get, 'https://api.stripe.com/v1/customers/cus_123')
      .with(headers: { 'Authorization' => 'Bearer sk_test_123' })
      .to_return(
        status: 200,
        body: { id: 'cus_123', object: 'customer' }.to_json,
        headers: { 'Request-Id' => 'abc-123-def-456' },
      )
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:stripe].reset_configuration!
    example.run
    Datadog.registry[:stripe].reset_configuration!
  end

  after do
    WebMock.allow_net_connect!
    WebMock.reset!
    WebMock.disable!
  end

  it 'traces the request' do
    Stripe::Customer.retrieve('cus_123')

    expect(spans).to have(1).items
    expect(span.name).to eq('stripe.request')
    expect(span.resource).to eq('stripe.request')
    expect(span.get_tag('stripe.request.id')).to eq('abc-123-def-456')
    expect(span.get_tag('stripe.request.http_status')).to eq('200')
    expect(span.get_tag('stripe.request.method')).to eq('get')
    expect(span.get_tag('stripe.request.path')).to eq('/v1/customers/cus_123')
    expect(span.get_tag('stripe.request.num_retries')).to eq('0')
    expect(span.status).to eq(0)
  end

  # dependent upon stripe/stripe-ruby#1168
  context 'when the stripe library includes the object name in the event' do
    let(:request_end_event_class_with_object_name) do
      Class.new(Stripe::Instrumentation::RequestEndEvent) do
        def object_name
          'customer'
        end
      end
    end

    before do
      stub_const('Stripe::Instrumentation::RequestEndEvent', request_end_event_class_with_object_name)
    end

    it 'traces the request' do
      Stripe::Customer.retrieve('cus_123')

      expect(spans).to have(1).items
      expect(span.name).to eq('stripe.request')
      expect(span.resource).to eq('stripe.customer')
      expect(span.get_tag('stripe.request.id')).to eq('abc-123-def-456')
      expect(span.get_tag('stripe.request.http_status')).to eq('200')
      expect(span.get_tag('stripe.request.method')).to eq('get')
      expect(span.get_tag('stripe.request.path')).to eq('/v1/customers/cus_123')
      expect(span.get_tag('stripe.request.num_retries')).to eq('0')
      expect(span.status).to eq(0)
    end
  end
end
