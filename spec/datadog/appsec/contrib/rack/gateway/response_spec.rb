# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/gateway/request'
require 'datadog/appsec/processor'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::Gateway::Response do
  let(:response) do
    described_class.new(
      'Ok',
      200,
      { 'Content-Type' => 'text/html' },
      active_context: instance_double(Datadog::AppSec::Processor::Context)
    )
  end

  describe '#body' do
    it 'returns the body' do
      expect(response.body).to eq('Ok')
    end
  end

  describe '#status' do
    it 'returns the status' do
      expect(response.status).to eq(200)
    end
  end

  describe '#headers' do
    it 'returns the headers' do
      expect(response.headers).to eq({ 'content-type' => 'text/html' })
    end
  end

  describe '#response' do
    it 'returns a rack response object' do
      expect(response.response).to be_a(Rack::Response)
    end
  end
end
