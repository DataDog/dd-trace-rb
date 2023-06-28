RSpec.describe Datadog::Tracing::Contrib::ActionView::Utils do
  describe '#normalize_template_name' do
    subject(:normalize_template_name) { described_class.normalize_template_name(name) }

    after { Datadog.configuration.tracing[:action_view].reset! }

    context 'with template path' do
      let(:name) { '/rails/app/views/welcome/index.html.erb' }

      it { is_expected.to eq('welcome/index.html.erb') }
    end

    context 'with nil template' do
      let(:name) { nil }

      it { is_expected.to be(nil) }
    end

    context 'with file name only' do
      let(:name) { 'index.html.erb' }

      it { is_expected.to eq('index.html.erb') }
    end

    context 'with template outside of `views/` directory' do
      let(:name) { '/rails/app/other/welcome/index.html.erb' }

      it { is_expected.to eq('index.html.erb') }
    end

    context 'with a custom template base path' do
      before { Datadog.configuration.tracing[:action_view][:template_base_path] = 'custom/' }

      context 'with template outside of `views/` directory' do
        let(:name) { '/rails/app/custom/welcome/index.html.erb' }

        it { is_expected.to eq('welcome/index.html.erb') }
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
