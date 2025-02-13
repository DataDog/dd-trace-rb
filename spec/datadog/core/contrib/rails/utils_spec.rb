require 'lib/datadog/core/contrib/rails/utils'
require 'rails/version'

RSpec.describe Datadog::Core::Contrib::Rails::Utils do
  describe 'railtie_supported?' do
    subject(:railtie_supported?) { described_class.railtie_supported? }

    context 'without Railtie loaded' do
      before do
        hide_const('::Rails::Railtie')
      end

      it { is_expected.to be false }
    end

    context 'with Railtie loaded' do
      before do
        stub_const('::Rails::Railtie', instance_double('::Rails::Railtie'))
      end

      it { is_expected.to be true }
    end
  end
end
