# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/scope'
require 'datadog/appsec/reactive/operation'
require 'datadog/appsec/contrib/rack/gateway/response'
require 'datadog/appsec/contrib/rack/reactive/response'

RSpec.describe Datadog::AppSec::Contrib::Rack::Reactive::Response do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:processor_context) { instance_double(Datadog::AppSec::Processor::Context) }
  let(:scope) { instance_double(Datadog::AppSec::Scope, processor_context: processor_context) }
  let(:body) { ['Ok'] }
  let(:headers) { { 'content-type' => 'text/html', 'set-cookie' => 'foo' } }

  let(:response) do
    Datadog::AppSec::Contrib::Rack::Gateway::Response.new(
      body,
      200,
      headers,
      scope: scope,
    )
  end

  describe '.publish' do
    it 'propagates response attributes to the operation' do
      expect(operation).to receive(:publish).with('response.status', 200)
      expect(operation).to receive(:publish).with(
        'response.headers',
        headers,
      )
      expect(operation).to receive(:publish).with(
        'response.body',
        nil,
      )

      described_class.publish(operation, response)
    end

    context 'JSON response' do
      let(:headers) { { 'content-type' => 'application/json', 'set-cookie' => 'foo' } }
      let(:body) { ['{"a":"b"}'] }

      context 'when parsed_response_body is enabled' do
        it 'propagates response attributes to the operation' do
          expect(operation).to receive(:publish).with('response.status', 200)
          expect(operation).to receive(:publish).with(
            'response.headers',
            headers,
          )
          expect(operation).to receive(:publish).with(
            'response.body',
            { 'a' => 'b' },
          )

          described_class.publish(operation, response)
        end
      end

      context 'when parsed_response_body is disabled' do
        around do |example|
          ClimateControl.modify('DD_API_SECURITY_PARSE_RESPONSE_BODY' => 'false') do
            example.run
          end
        end

        it 'propagates response attributes to the operation' do
          expect(operation).to receive(:publish).with('response.status', 200)
          expect(operation).to receive(:publish).with(
            'response.headers',
            headers,
          )
          expect(operation).to receive(:publish).with(
            'response.body',
            nil,
          )

          described_class.publish(operation, response)
        end
      end
    end
  end

  describe '.subscribe' do
    context 'not all addresses have been published' do
      it 'does not call the waf context' do
        expect(operation).to receive(:subscribe).with(
          'response.status',
          'response.headers',
          'response.body'
        ).and_call_original
        expect(processor_context).to_not receive(:run)
        described_class.subscribe(operation, processor_context)
      end
    end

    context 'waf arguments' do
      before do
        expect(operation).to receive(:subscribe).and_call_original
      end

      let(:waf_result) { double(:waf_result, status: :ok, timeout: false) }

      context 'all addresses have been published' do
        let(:expected_waf_arguments) do
          {
            'server.response.status' => '200',
            'server.response.headers' => {
              'content-type' => 'text/html',
              'set-cookie' => 'foo',
            },
            'server.response.headers.no_cookies' => {
              'content-type' => 'text/html',
            },
          }
        end

        it 'does call the waf context with the right arguments' do
          expect(processor_context).to receive(:run).with(
            expected_waf_arguments,
            Datadog.configuration.appsec.waf_timeout
          ).and_return(waf_result)
          described_class.subscribe(operation, processor_context)
          result = described_class.publish(operation, response)
          expect(result).to be_nil
        end
      end

      context 'JSON response' do
        let(:headers) { { 'content-type' => 'application/json', 'set-cookie' => 'foo' } }
        let(:body) { ['{"a":"b"}'] }

        context 'when parsed_response_body is enabled' do
          context 'all addresses have been published' do
            let(:expected_waf_arguments) do
              {
                'server.response.status' => '200',
                'server.response.headers' => {
                  'content-type' => 'application/json',
                  'set-cookie' => 'foo',
                },
                'server.response.headers.no_cookies' => {
                  'content-type' => 'application/json',
                },
                'server.response.body' => { 'a' => 'b' },
              }
            end

            it 'does call the waf context with the right arguments' do
              expect(processor_context).to receive(:run).with(
                expected_waf_arguments,
                Datadog.configuration.appsec.waf_timeout
              ).and_return(waf_result)
              described_class.subscribe(operation, processor_context)
              result = described_class.publish(operation, response)
              expect(result).to be_nil
            end
          end

          context 'when unparsable response body' do
            # since the body is not all string values we bail out in Datadog::AppSec::Contrib::Rack::Gateway::Response
            let(:body) do
              [proc {}]
            end

            let(:expected_waf_arguments) do
              {
                'server.response.status' => '200',
                'server.response.headers' => {
                  'content-type' => 'application/json',
                  'set-cookie' => 'foo',
                },
                'server.response.headers.no_cookies' => {
                  'content-type' => 'application/json',
                }
              }
            end

            it 'does call the waf context with the right arguments' do
              expect(processor_context).to receive(:run).with(
                expected_waf_arguments,
                Datadog.configuration.appsec.waf_timeout
              ).and_return(waf_result)
              described_class.subscribe(operation, processor_context)
              result = described_class.publish(operation, response)
              expect(result).to be_nil
            end
          end
        end

        context 'when parsed_response_body is disabled' do
          around do |example|
            ClimateControl.modify('DD_API_SECURITY_PARSE_RESPONSE_BODY' => 'false') do
              example.run
            end
          end

          let(:expected_waf_arguments) do
            {
              'server.response.status' => '200',
              'server.response.headers' => {
                'content-type' => 'application/json',
                'set-cookie' => 'foo',
              },
              'server.response.headers.no_cookies' => {
                'content-type' => 'application/json',
              },
            }
          end

          it 'does call the waf context with the right arguments' do
            expect(processor_context).to receive(:run).with(
              expected_waf_arguments,
              Datadog.configuration.appsec.waf_timeout
            ).and_return(waf_result)
            described_class.subscribe(operation, processor_context)
            result = described_class.publish(operation, response)
            expect(result).to be_nil
          end
        end
      end
    end

    context 'waf result is a match' do
      it 'yields result and no blocking action' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: [])
        expect(processor_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, processor_context) do |result|
          expect(result).to eq(waf_result)
        end
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end

      it 'yields result and blocking action. The publish method catches the resul as well' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :match, timeout: false, actions: ['block'])
        expect(processor_context).to receive(:run).and_return(waf_result)
        described_class.subscribe(operation, processor_context) do |result|
          expect(result).to eq(waf_result)
        end
        block = described_class.publish(operation, response)
        expect(block).to eq(true)
      end
    end

    context 'waf result is ok' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :ok, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_call' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_call, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_rule, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end

    context 'waf result is invalid_flow' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :invalid_flow, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end

    context 'waf result is no_rule' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :no_rule, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end

    context 'waf result is unknown' do
      it 'does not yield' do
        expect(operation).to receive(:subscribe).and_call_original

        waf_result = double(:waf_result, status: :foo, timeout: false)
        expect(processor_context).to receive(:run).and_return(waf_result)
        expect { |b| described_class.subscribe(operation, processor_context, &b) }.not_to yield_control
        result = described_class.publish(operation, response)
        expect(result).to be_nil
      end
    end
  end
end
