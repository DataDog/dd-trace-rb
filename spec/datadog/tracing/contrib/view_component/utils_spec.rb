RSpec.describe Datadog::Tracing::Contrib::ViewComponent::Utils do
  describe '#normalize_component_identifier' do
    subject(:normalize_component_identifier) { described_class.normalize_component_identifier(name) }

    after { Datadog.configuration.tracing[:view_component].reset! }

    context 'with component identifer' do
      let(:name) { '/rails/app/components/welcome/my_component.rb' }

      it { is_expected.to eq('welcome/my_component.rb') }
    end

    context 'with nil identifer' do
      let(:name) { nil }

      it { is_expected.to be(nil) }
    end

    context 'with file name only' do
      let(:name) { 'my_component.rb' }

      it { is_expected.to eq('my_component.rb') }
    end

    context 'with identifer outside of `components/` directory' do
      let(:name) { '/rails/app/other/welcome/my_component.rb' }

      it { is_expected.to eq('my_component.rb') }
    end

    context 'with a custom component base path' do
      before { Datadog.configuration.tracing[:view_component][:component_base_path] = 'custom/' }

      context 'with component outside of `components/` directory' do
        let(:name) { '/rails/app/custom/welcome/my_component.rb' }

        it { is_expected.to eq('welcome/my_component.rb') }
      end
    end

    context 'with a non-string-like argument' do
      let(:name) { :not_a_string }

      it 'stringifies arguments' do
        is_expected.to eq('not_a_string')
      end
    end
  end
end
