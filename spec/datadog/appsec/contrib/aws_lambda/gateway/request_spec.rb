# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/gateway/request'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Gateway::Request do
  describe '#form_hash' do
    subject(:form_hash) { described_class.new(event).form_hash }

    context 'when body is valid JSON' do
      let(:event) do
        {
          'headers' => {'content-type' => 'application/json'},
          'body' => '{"key":"value"}',
        }
      end

      it { expect(form_hash).to eq({'key' => 'value'}) }
    end

    context 'when body is invalid JSON' do
      let(:event) do
        {
          'headers' => {'content-type' => 'application/json'},
          'body' => 'not json',
        }
      end

      it 'reports error to telemetry' do
        expect(Datadog::AppSec.telemetry).to receive(:report)
          .with(kind_of(Exception), description: 'AppSec: Failed to parse body')

        form_hash
      end
    end

    context 'when body is URL-encoded with duplicate keys' do
      let(:event) do
        {
          'headers' => {'content-type' => 'application/x-www-form-urlencoded'},
          'body' => 'foo=bar&foo=baz',
        }
      end

      it { expect(form_hash).to eq({'foo' => ['bar', 'baz']}) }
    end
  end

  describe '#fullpath' do
    subject(:fullpath) { described_class.new(event).fullpath }

    context 'when v1 queryStringParameters contain special characters' do
      let(:event) do
        {
          'headers' => {},
          'path' => '/search',
          'queryStringParameters' => {'tag' => 'a&b', 'q' => 'hello world'},
        }
      end

      it { expect(fullpath).to eq('/search?tag=a%26b&q=hello+world') }
    end
  end
end
