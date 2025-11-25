require 'datadog/appsec/response'

RSpec.describe Datadog::AppSec::Response do
  describe '.from_interrupt_params' do
    context 'when response is a redirect request' do
      let(:response) { described_class.from_interrupt_params(params, 'text/html') }
      let(:params) do
        {
          'location' => 'example.com',
          'status_code' => '303',
          'security_response_id' => '00000000-0000-0000-0000-000000000000'
        }
      end

      it 'returns response with redirect attributes' do
        expect(response.status).to eq(303)
        expect(response.body).to eq([])
        expect(response.headers).to include('Location' => 'example.com')
      end
    end

    context 'when response is a redirect request with non 3xx code' do
      let(:response) { described_class.from_interrupt_params(params, 'text/html') }
      let(:params) do
        {
          'location' => 'example.com',
          'status_code' => '202',
          'security_response_id' => '00000000-0000-0000-0000-000000000000'
        }
      end

      it { expect(response.status).to eq(303) }
    end

    context 'when response is a redirect request with security response ID value' do
      let(:response) { described_class.from_interrupt_params(params, 'text/html') }
      let(:params) do
        {
          'location' => 'example.com?blocked_with=[security_response_id]',
          'status_code' => '303',
          'security_response_id' => '00000000-0000-0000-0000-000000000000'
        }
      end

      it { expect(response.headers).to include('Location' => 'example.com?blocked_with=00000000-0000-0000-0000-000000000000') }
    end

    context 'when response is a redirect request without security response ID value' do
      let(:response) { described_class.from_interrupt_params(params, 'text/html') }
      let(:params) do
        {
          'location' => 'example.com?blocked_with=[security_response_id]',
          'status_code' => '303',
          'security_response_id' => nil
        }
      end

      it { expect(response.headers).to include('Location' => 'example.com?blocked_with=[security_response_id]') }
    end

    context 'when response is a block response' do
      let(:response) { described_class.from_interrupt_params(params, 'text/html') }
      let(:params) do
        {
          'type' => 'html',
          'status_code' => '100',
          'security_response_id' => '00000000-0000-0000-0000-000000000000'
        }
      end

      it 'returns response with block attributes' do
        expect(response.status).to eq(100)
        expect(response.headers).to include('Content-Type' => 'text/html')
        expect(response.body[0]).to match(
          /<p class="security-response-id">.*: 00000000-0000-0000-0000-000000000000/
        )
      end
    end

    describe '.status' do
      context 'when response fallbacks to all defaults' do
        let(:response) { described_class.from_interrupt_params({}, 'text/html') }

        it { expect(response.status).to eq(403) }
      end
    end

    describe '.body' do
      context 'when Accept header value is not supported' do
        let(:response) do
          described_class.from_interrupt_params(
            {'security_response_id' => '00000000-0000-0000-0000-000000000000'}, 'application/xml'
          )
        end

        it 'returns default json template with security response ID' do
          expect(response.body[0]).to match(
            /{"errors":.*,"security_response_id":"00000000-0000-0000-0000-000000000000".*}/
          )
        end
      end

      context 'when Accept header value is text/html' do
        let(:response) do
          described_class.from_interrupt_params(
            {'security_response_id' => '00000000-0000-0000-0000-000000000000'}, 'text/html'
          )
        end

        it 'returns HTML template with security response ID' do
          expect(response.body[0]).to match(
            /.*<!DOCTYPE html>\n.*<p class="security-response-id">.*: 00000000-0000-0000-0000-000000000000/m
          )
        end
      end

      context 'when Accept header value is application/json' do
        let(:response) do
          described_class.from_interrupt_params(
            {'security_response_id' => '00000000-0000-0000-0000-000000000000'}, 'application/json'
          )
        end

        it 'returns default json template with security response ID' do
          expect(response.body[0]).to match(
            /{"errors":.*,"security_response_id":"00000000-0000-0000-0000-000000000000".*}/
          )
        end
      end

      context 'when Accept header value is text/plain' do
        let(:response) do
          described_class.from_interrupt_params(
            {'security_response_id' => '00000000-0000-0000-0000-000000000000'}, 'text/plain'
          )
        end

        it 'returns default json template with security response ID' do
          expect(response.body[0]).to match(
            /You've been blocked.*Security Response ID: 00000000-0000-0000-0000-000000000000.*/m
          )
        end
      end

      context 'when default template is changed to custom' do
        around do |example|
          RSpec::Mocks.with_temporary_scope do
            # NOTE: Here we avoid creating real file and deleting it afterwards
            #       instead we leverage knowledge of internals without breaking
            #       the setter logic
            expect(File).to receive(:exist?).with('/tmp/custom.txt').and_return(true)
            expect(File).to receive(:binread).with('/tmp/custom.txt')
              .and_return("Blocked, that's an ID: [security_response_id]")

            allow(File).to receive(:exist?).with(any_args).and_call_original
            allow(File).to receive(:binread).with(any_args).and_call_original

            Datadog.configure { |c| c.appsec.block.templates.text = '/tmp/custom.txt' }
            example.run
          ensure
            Datadog.configuration.reset!
          end
        end

        let(:response) do
          described_class.from_interrupt_params(
            {'security_response_id' => '00000000-0000-0000-0000-000000000000'}, 'text/plain'
          )
        end

        it 'returns custom template with security response ID' do
          expect(response.body[0]).to match(
            /Blocked, that's an ID: 00000000-0000-0000-0000-000000000000/
          )
        end
      end
    end

    describe '.headers' do
      {
        nil => 'application/json',
        '*/*' => 'application/json',
        'text/*' => 'text/html',
        'text/html' => 'text/html',
        'invalid' => 'application/json',
        'image/webp' => 'application/json',
        'application/*' => 'application/json',
        'text/*;q=0.7, application/*;q=0.8, */*;q=0.9' => 'application/json',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' => 'text/html',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' => 'text/html',
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' => 'text/html',
      }.each do |header, expected|
        context "when Accept header is #{header.inspect}" do
          let(:response) { described_class.from_interrupt_params({}, header) }

          it { expect(response.headers).to include('Content-Type' => expected) }
        end
      end
    end
  end
end
