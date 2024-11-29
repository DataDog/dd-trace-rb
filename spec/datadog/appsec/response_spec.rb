require 'datadog/appsec/response'

RSpec.describe Datadog::AppSec::Response do
  describe '.negotiate' do
    let(:env) { double }

    before do
      allow(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
      allow(env).to receive(:[]).with('HTTP_ACCEPT').and_return('text/html')
    end

    describe 'configured actions' do
      describe 'block' do
        let(:actions) do
          {
            'block_request' => {
              'type' => type,
              'status_code' => status_code
            }
          }
        end

        let(:type) { 'html' }
        let(:status_code) { 100 }

        context 'status_code' do
          subject(:status) { described_class.negotiate(env, actions).status }

          it { is_expected.to eq 100 }

          context 'configured action do not have status defined. Defaults to 403' do
            let(:status_code) { nil }

            it { is_expected.to eq 403 }
          end
        end

        context 'body' do
          subject(:body) { described_class.negotiate(env, actions).body }

          it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :html)] }

          context 'type is auto it uses the HTTP_ACCEPT to decide the result' do
            let(:type) { 'auto' }

            before do
              expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
              expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return('application/json')
            end

            it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :json)] }
          end
        end

        context 'headers' do
          subject(:header) { described_class.negotiate(env, actions).headers['Content-Type'] }

          it { is_expected.to eq 'text/html' }

          context 'type is auto it uses the HTTP_ACCEPT to decide the result' do
            let(:type) { 'auto' }

            before do
              expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
              expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return('application/json')
            end

            it { is_expected.to eq 'application/json' }
          end
        end

        context 'no configured actions' do
          let(:actions) { {} }
          subject(:response) { described_class.negotiate(env, actions) }

          it 'uses default response' do
            expect(response.status).to eq 403
            expect(response.body).to eq [Datadog::AppSec::Assets.blocked(format: :html)]
            expect(response.headers['Content-Type']).to eq 'text/html'
          end
        end
      end

      describe 'redirect_request' do
        let(:actions) do
          {
            'redirect_request' => {
              'location' => location,
              'status_code' => status_code
            }
          }
        end

        let(:location) { 'foo' }
        let(:status_code) { 303 }

        context 'status_code' do
          subject(:status) { described_class.negotiate(env, actions).status }

          it { is_expected.to eq 303 }

          context 'when status code do not starts with 3' do
            let(:status_code) { 202 }

            it { is_expected.to eq 303 }
          end
        end

        context 'body' do
          subject(:body) { described_class.negotiate(env, actions).body }

          it { is_expected.to eq [] }
        end

        context 'headers' do
          subject(:headers) { described_class.negotiate(env, actions).headers }

          context 'Content-Type' do
            before do
              expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
              expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return('application/json')
            end

            it 'uses the one from HTTP_ACCEPT header' do
              expect(headers['Content-Type']).to eq('application/json')
            end
          end

          context 'Location' do
            it 'uses the one from the configuration' do
              expect(headers['Location']).to eq('foo')
            end
          end
        end

        context 'location is empty' do
          let(:location) { '' }

          subject(:response) { described_class.negotiate(env, actions) }

          it 'uses default response' do
            expect(response.status).to eq 403
            expect(response.body).to eq [Datadog::AppSec::Assets.blocked(format: :html)]
            expect(response.headers['Content-Type']).to eq 'text/html'
          end
        end
      end
    end

    describe '.status' do
      subject(:status) { described_class.negotiate(env, {}).status }

      it { is_expected.to eq 403 }
    end

    describe '.body' do
      subject(:body) { described_class.negotiate(env, {}).body }

      before do
        expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
        expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return(accept)
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
        let(:accept) { 'application/xml' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :json)] }
      end

      context('with Accept: text/html') do
        let(:accept) { 'text/html' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :html)] }

        it_behaves_like 'with custom response body', :html
      end

      context('with Accept: application/json') do
        let(:accept) { 'application/json' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :json)] }

        it_behaves_like 'with custom response body', :json
      end

      context('with Accept: text/plain') do
        let(:accept) { 'text/plain' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :text)] }

        it_behaves_like 'with custom response body', :text
      end
    end

    describe ".headers['Content-Type']" do
      subject(:content_type) { described_class.negotiate(env, {}).headers['Content-Type'] }

      before do
        expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(respond_to?(:accept))

        if respond_to?(:accept)
          expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return(accept)
        else
          expect(env).to_not receive(:[]).with('HTTP_ACCEPT')
        end
      end

      context('with Accept: text/html') do
        let(:accept) { 'text/html' }

        it { is_expected.to eq accept }
      end

      context('with Accept: application/json') do
        let(:accept) { 'application/json' }

        it { is_expected.to eq accept }
      end

      context('with Accept: text/plain') do
        let(:accept) { 'text/plain' }

        it { is_expected.to eq accept }
      end

      context('without Accept header') do
        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: */*') do
        let(:accept) { '*/*' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: text/*') do
        let(:accept) { 'text/*' }

        it { is_expected.to eq 'text/html' }
      end

      context('with Accept: application/*') do
        let(:accept) { 'application/*' }

        it { is_expected.to eq 'application/json' }
      end

      context('with unparseable Accept header') do
        let(:accept) { 'invalid' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Accept: text/*;q=0.7, application/*;q=0.8, */*;q=0.9') do
        let(:accept) { 'text/*;q=0.7, application/*;q=0.8, */*;q=0.9' }

        it { is_expected.to eq 'application/json' }
      end

      context('with unsupported Accept header') do
        let(:accept) { 'image/webp' }

        it { is_expected.to eq 'application/json' }
      end

      context('with Mozilla Firefox Accept') do
        let(:accept) { 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8' }

        it { is_expected.to eq 'text/html' }
      end

      context('with Google Chrome Accept') do
        let(:accept) { 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' } # rubocop:disable Layout/LineLength

        it { is_expected.to eq 'text/html' }
      end

      context('with Apple Safari Accept') do
        let(:accept) { 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' }

        it { is_expected.to eq 'text/html' }
      end
    end
  end
end
