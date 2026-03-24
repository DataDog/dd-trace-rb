# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/gateway/watcher'
require 'datadog/appsec/contrib/aws_lambda/gateway/request'
require 'datadog/appsec/contrib/aws_lambda/gateway/response'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  describe '.watch_request' do
    context 'when AppSec context is not active' do
      before do
        allow(Datadog::AppSec::Context).to receive(:active).and_return(nil)
        described_class.watch_request(gateway)
      end

      let(:gateway_request) do
        Datadog::AppSec::Contrib::AwsLambda::Gateway::Request.new(
          'headers' => {},
          'httpMethod' => 'GET',
          'path' => '/',
        )
      end

      it { expect { gateway.push('aws_lambda.request.start', gateway_request) }.to_not raise_error }
    end
  end

  describe '.watch_response' do
    context 'when context is nil' do
      before { described_class.watch_response(gateway) }

      let(:gateway_response) do
        Datadog::AppSec::Contrib::AwsLambda::Gateway::Response.new(
          {'statusCode' => 200, 'headers' => {}},
          context: nil,
        )
      end

      it { expect { gateway.push('aws_lambda.response.start', gateway_response) }.to_not raise_error }
    end
  end
end
