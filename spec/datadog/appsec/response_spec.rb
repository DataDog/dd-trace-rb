require 'datadog/appsec/response'

RSpec.describe Datadog::AppSec::Response do
  describe '.from_interrupt_params' do
    let(:http_accept_header) { 'text/html' }

    describe 'configured interrupt_params' do
      describe 'block' do
        let(:interrupt_params) do
          {
            'type' => type,
            'status_code' => status_code,
            'security_response_id' => security_response_id
          }
        end

        let(:type) { 'html' }
        let(:status_code) { '100' }
        let(:security_response_id) { '73bb7b99-52f6-43ea-998c-6cbc6b80f520' }

        context 'status_code' do
          subject(:status) { described_class.from_interrupt_params(interrupt_params, http_accept_header).status }

          it { is_expected.to eq 100 }

          context 'configured action do not have status defined. Defaults to 403' do
            let(:status_code) { nil }

            it { is_expected.to eq 403 }
          end
        end

        context 'body' do
          subject(:body) { described_class.from_interrupt_params(interrupt_params, http_accept_header).body }

          it 'includes security response ID in the response body' do
            expect(body).to match_array([include(security_response_id)])
          end

          context 'type is auto it uses the HTTP_ACCEPT to decide the result' do
            let(:type) { 'auto' }
            let(:http_accept_header) { 'application/json' }

            it 'includes security response ID in the response body' do
              expect(body).to match_array([include(security_response_id)])
            end

            it 'returns the response body with correct content type' do
              expect(body).to eq([
                Datadog::AppSec::Assets
                  .blocked(format: :json)
                  .gsub(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER, security_response_id)
              ])
            end
          end
        end

        context 'headers' do
          subject(:header) do
            described_class.from_interrupt_params(interrupt_params, http_accept_header).headers['Content-Type']
          end

          it { is_expected.to eq 'text/html' }

          context 'type is auto it uses the HTTP_ACCEPT to decide the result' do
            let(:type) { 'auto' }
            let(:http_accept_header) { 'application/json' }

            it { is_expected.to eq 'application/json' }
          end
        end

        context 'empty interrupt_params' do
          let(:interrupt_params) { {} }
          subject(:response) { described_class.from_interrupt_params(interrupt_params, http_accept_header) }

          it 'uses default response replaces placeholders in the template' do
            expect(response.status).to eq 403
            expect(response.headers['Content-Type']).to eq 'text/html'
          end

          it 'does not render security response ID placeholders' do
            expect(response.body).not_to match_array([include(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER)])
          end
        end
      end

      describe 'redirect_request' do
        let(:interrupt_params) do
          {
            'location' => location,
            'status_code' => status_code,
            'security_response_id' => security_response_id
          }
        end

        let(:location) { 'example.com' }
        let(:status_code) { '303' }
        let(:security_response_id) { '73bb7b99-52f6-43ea-998c-6cbc6b80f520' }

        context 'status_code' do
          subject(:status) { described_class.from_interrupt_params(interrupt_params, http_accept_header).status }

          it { is_expected.to eq 303 }

          context 'when status code do not starts with 3' do
            let(:status_code) { '202' }

            it { is_expected.to eq 303 }
          end
        end

        context 'body' do
          subject(:body) { described_class.from_interrupt_params(interrupt_params, http_accept_header).body }

          it { is_expected.to eq [] }
        end

        context 'headers' do
          subject(:headers) { described_class.from_interrupt_params(interrupt_params, http_accept_header).headers }

          it 'sets Location header' do
            expect(headers['Location']).to eq("example.com")
          end

          context 'when location contains security response id placeholder' do
            let(:location) { 'example.com?security_response_id=[security_response_id]' }

            it 'sets Location header with substituted security response id placeholder' do
              expect(headers['Location']).to eq("example.com?security_response_id=#{security_response_id}")
            end

            context 'when security_response_id is missing in action params' do
              let(:security_response_id) { nil }

              it 'sets Location header without removing security response id placeholder' do
                expect(headers['Location']).to eq('example.com?security_response_id=[security_response_id]')
              end
            end
          end
        end
      end
    end

    describe '.status' do
      subject(:status) { described_class.from_interrupt_params({}, http_accept_header).status }

      it { is_expected.to eq 403 }
    end

    describe '.body' do
      let(:security_response_id) { SecureRandom.uuid }

      subject(:body) do
        described_class.from_interrupt_params(
          {'security_response_id' => security_response_id},
          http_accept_header
        ).body
      end

      shared_examples_for 'with custom response body' do |type|
        before do
          File.write("test.#{type}", 'testing')
          Datadog.configuration.appsec.block.templates.send("#{type}=", "test.#{type}")
        end

        after do
          File.delete("test.#{type}")
          Datadog.configuration.appsec.reset!
        end

        it { is_expected.to eq ['testing'] }
      end

      context 'with unsupported Accept headers' do
        let(:http_accept_header) { 'application/xml' }

        it 'returns default json template with security response ID' do
          expect(body).to eq([
            Datadog::AppSec::Assets
              .blocked(format: :json)
              .gsub(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER, security_response_id)
          ])
        end
      end

      context('with Accept: text/html') do
        let(:http_accept_header) { 'text/html' }

        it 'returns default html template with security response ID' do
          expect(body).to eq([
            Datadog::AppSec::Assets
              .blocked(format: :html)
              .gsub(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER, security_response_id)
          ])
        end

        it_behaves_like 'with custom response body', :html
      end

      context('with Accept: application/json') do
        let(:http_accept_header) { 'application/json' }

        it 'returns default json template with security response ID' do
          expect(body).to eq([
            Datadog::AppSec::Assets
              .blocked(format: :json)
              .gsub(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER, security_response_id)
          ])
        end

        it_behaves_like 'with custom response body', :json
      end

      context('with Accept: text/plain') do
        let(:http_accept_header) { 'text/plain' }

        it 'returns default text template with security response ID' do
          expect(body).to eq([
            Datadog::AppSec::Assets
              .blocked(format: :text)
              .gsub(Datadog::AppSec::Response::SECURITY_RESPONSE_ID_PLACEHOLDER, security_response_id)
          ])
        end

        it_behaves_like 'with custom response body', :text
      end
    end

    describe ".headers['Content-Type']" do
      subject(:content_type) { described_class.from_interrupt_params({}, http_accept_header).headers['Content-Type'] }

      context('with Accept: text/html') do
        let(:http_accept_header) { 'text/html' }

        it { is_expected.to eq http_accept_header }
      end

      context('with Accept: application/json') do
        let(:http_accept_header) { 'application/json' }

        it { is_expected.to eq http_accept_header }
      end

      context('with Accept: text/plain') do
        let(:http_accept_header) { 'text/plain' }

        it { is_expected.to eq http_accept_header }
      end

      context('without Accept header') do
        let(:http_accept_header) { nil }

        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: */*') do
        let(:http_accept_header) { '*/*' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: text/*') do
        let(:http_accept_header) { 'text/*' }

        it { is_expected.to eq 'text/html' }
      end

      context('with Accept: application/*') do
        let(:http_accept_header) { 'application/*' }

        it { is_expected.to eq 'application/json' }
      end

      context('with unparseable Accept header') do
        let(:http_accept_header) { 'invalid' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: text/*;q=0.7, application/*;q=0.8, */*;q=0.9') do
        let(:http_accept_header) { 'text/*;q=0.7, application/*;q=0.8, */*;q=0.9' }

        it { is_expected.to eq 'application/json' }
      end

      context('with unsupported Accept header') do
        let(:http_accept_header) { 'image/webp' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Mozilla Firefox Accept') do
        let(:http_accept_header) { 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' }

        it { is_expected.to eq 'text/html' }
      end

      context('with Google Chrome Accept') do
        let(:http_accept_header) { 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' } # rubocop:disable Layout/LineLength

        it { is_expected.to eq 'text/html' }
      end

      context('with Apple Safari Accept') do
        let(:http_accept_header) { 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }

        it { is_expected.to eq 'text/html' }
      end
    end
  end
end
