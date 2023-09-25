# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/rack/gateway/response'
require 'datadog/appsec/scope'
require 'rack'

RSpec.describe Datadog::AppSec::Contrib::Rack::Gateway::Response do
  let(:body) { ['Ok'] }
  let(:content_type) { 'text/html' }

  let(:response) do
    described_class.new(
      body,
      200,
      { 'Content-Type' => content_type },
      scope: instance_double(Datadog::AppSec::Scope)
    )
  end

  describe '#body' do
    it 'returns the body' do
      expect(response.body).to eq(['Ok'])
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

  describe '#parsed_body' do
    context 'json response' do
      let(:content_type) { 'appplication/json' }

      context 'all body parts are strings' do
        let(:body) { ['{ "f', 'oo":', ' "ba', 'r" }'] }

        it 'returns a hash object' do
          expect(response.parsed_body).to eq({ 'foo' => 'bar' })
        end
      end

      context 'not all body parts are strings' do
        let(:body_proc) { proc { ' "ba' } }
        let(:body) { ['{ "f', 'oo":', body_proc, 'r" }'] }

        it 'returns nil' do
          expect(response.parsed_body).to be_nil
        end
      end
    end

    context 'text response' do
      context 'disabled parse_response_body' do
        before do
          expect(Datadog.configuration.appsec).to receive(:parse_response_body).and_return(false)
        end

        it 'returns nil' do
          expect(response.parsed_body).to be_nil
        end
      end

      context 'all body parts are strings' do
        let(:body) { ['{ "f', 'oo":', ' "ba', 'r" }'] }

        it 'returns a string' do
          expect(response.parsed_body).to eq('{ "foo": "bar" }')
        end
      end

      context 'not all body parts are strings' do
        let(:body_proc) { proc { ' "ba' } }
        let(:body) { ['{ "f', 'oo":', body_proc, 'r" }'] }

        it 'returns nil' do
          expect(response.parsed_body).to be_nil
        end
      end
    end

    context 'non supported response type' do
      let(:content_type) { 'video/mpeg' }

      it 'returns nil' do
        expect(response.parsed_body).to be_nil
      end
    end

    context 'with a body that is not an Array' do
      let(:body) { proc { ' "ba' } }

      it 'returns nil' do
        expect(response.parsed_body).to be_nil
      end
    end

    context 'with a body that is a Rack::BodyProxy' do
      let(:body) { Rack::BodyProxy.new(['{ "foo":  "bar" }']) }

      it 'returns a string' do
        expect(response.parsed_body).to eq('{ "foo":  "bar" }')
      end
    end

    context 'with a body that inherits from Array' do
      let(:my_body_class) do
        Class.new(Array) do
        end
      end

      let(:body) do
        my_body_class.new
      end

      it 'returns nil' do
        expect(response.parsed_body).to be_nil
      end
    end
  end
end
