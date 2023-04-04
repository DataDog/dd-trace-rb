require 'lib/datadog/tracing/contrib/rails/utils'
require 'rails/version'

RSpec.describe Datadog::Tracing::Contrib::Rails::Utils do
  describe 'railtie_supported?' do
    subject(:railtie_supported?) { described_class.railtie_supported? }

    context 'on rails 2 and below' do
      before { stub_const('::Rails::VERSION::MAJOR', 2) }

      it { is_expected.to be false }
    end

    context 'on rails 3 and above' do
      before do
        stub_const('::Rails::VERSION::MAJOR', 3)
        stub_const('::Rails::Railtie', instance_double('::Rails::Railtie'))
      end

      it { is_expected.to be true }
    end
  end
end
