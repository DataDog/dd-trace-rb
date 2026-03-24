# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/aws_lambda/gateway/watcher'

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }

  describe '.activate_context' do
    before do
      allow(Datadog::AppSec).to receive(:security_engine).and_return(security_engine)
      allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
      allow(Datadog::Tracing).to receive(:active_span).and_return(span)
      described_class.activate_context(gateway)
    end

    let(:event) { {'headers' => {}, 'httpMethod' => 'GET', 'path' => '/'} }

    context 'when security engine is available' do
      let(:security_engine) { instance_double(Datadog::AppSec::SecurityEngine::Engine, new_runner: runner) }
      let(:runner) { double('runner', finalize!: nil) }
      let(:trace) { double('trace') }
      let(:span) { double('span', set_metric: nil) }

      after { Datadog::AppSec::Context.deactivate }

      it 'activates AppSec context' do
        gateway.push('aws_lambda.request.start', event)
        expect(Datadog::AppSec::Context.active).to be_a(Datadog::AppSec::Context)
      end

      it 'sets appsec enabled metric on span' do
        gateway.push('aws_lambda.request.start', event)
        expect(span).to have_received(:set_metric).with('_dd.appsec.enabled', 1)
      end
    end

    context 'when security engine is not available' do
      let(:security_engine) { nil }
      let(:trace) { nil }
      let(:span) { nil }

      it 'does not activate context' do
        gateway.push('aws_lambda.request.start', event)
        expect(Datadog::AppSec::Context.active).to be_nil
      end
    end
  end

  describe '.handle_request' do
    before { described_class.handle_request(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { gateway.push('aws_lambda.request.start', {}) }.to_not raise_error }
    end
  end

  describe '.handle_response' do
    before { described_class.handle_response(gateway) }

    context 'when AppSec context is not active' do
      before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

      it { expect { gateway.push('aws_lambda.response.start', {}) }.to_not raise_error }
    end
  end
end
