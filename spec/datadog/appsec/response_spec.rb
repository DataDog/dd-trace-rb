require 'datadog/appsec/response'

RSpec.describe Datadog::AppSec::Response do
  describe '.negotiate' do
    let(:env) { double }

    before do
      allow(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
      allow(env).to receive(:[]).with('HTTP_ACCEPT').and_return('text/html')
    end

    describe '.status' do
      subject(:content_type) { described_class.negotiate(env).status }

      it { is_expected.to eq 403 }
    end

    describe '.body' do
      subject(:body) { described_class.negotiate(env).body }

      before do
        expect(env).to receive(:key?).with('HTTP_ACCEPT').and_return(true)
        expect(env).to receive(:[]).with('HTTP_ACCEPT').and_return(accept)
      end

      context('with Accept: text/html') do
        let(:accept) { 'text/html' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :html)] }
      end

      context('with Accept: application/json') do
        let(:accept) { 'application/json' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :json)] }
      end

      context('with Accept: text/plain') do
        let(:accept) { 'text/plain' }

        it { is_expected.to eq [Datadog::AppSec::Assets.blocked(format: :text)] }
      end
    end

    describe ".headers['Content-Type']" do
      subject(:content_type) { described_class.negotiate(env).headers['Content-Type'] }

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
