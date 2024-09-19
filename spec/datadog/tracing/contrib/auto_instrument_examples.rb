RSpec.shared_examples 'rails sub-gem auto_instrument?' do
  context 'auto_instrument?' do
    subject(:auto_instrument?) { integration.auto_instrument? }

    context 'outside of a rails application' do
      before do
        allow(Datadog::Tracing::Contrib::Rails::Utils).to receive(:railtie_supported?).and_return(false)
      end

      it { is_expected.to be(true) }
    end

    context 'when within a rails application' do
      before do
        allow(Datadog::Tracing::Contrib::Rails::Utils).to receive(:railtie_supported?).and_return(true)
      end

      it { is_expected.to be(false) }
    end
  end
end
