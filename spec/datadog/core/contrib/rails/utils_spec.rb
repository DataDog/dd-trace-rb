require 'lib/datadog/core/contrib/rails/utils'
require 'rails/version'
require 'active_support/core_ext/string/inflections'

RSpec.describe Datadog::Core::Contrib::Rails::Utils do
  describe 'app_name' do
    subject(:app_name) { described_class.app_name }

    let(:namespace_name) { 'custom_app' }
    let(:application_class) { double('custom rails class', module_parent_name: namespace_name) }

    let(:application) { double('custom rails', class: application_class) }

    # TODO: This can be refactored in the future to use a real Rails application class instead of stubs.
    let(:rails_module) do
      version_major = 7
      application_instance = application
      Module.new do
        version_module = Module.new do
          const_set(:MAJOR, version_major)
        end

        const_set(:VERSION, version_module)
        define_singleton_method(:application) { application_instance }
      end
    end

    before do
      stub_const('::Rails', rails_module)
    end

    context 'when namespace is available' do
      it { is_expected.to eq('custom_app') }
    end

    context 'when namespace is nil' do
      let(:namespace_name) { nil }

      it { is_expected.to be_nil }
    end

    context 'when Rails lookup raises an error' do
      before do
        allow(rails_module).to receive(:application).and_raise(StandardError)
      end

      it { is_expected.to be_nil }
    end
  end

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
