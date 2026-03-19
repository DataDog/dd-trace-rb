require 'lib/datadog/core/contrib/rails/utils'
require 'rails/version'
require 'active_support/core_ext/string/inflections'

RSpec.describe Datadog::Core::Contrib::Rails::Utils do
  describe 'app_name' do
    subject(:app_name) { described_class.app_name }

    let(:namespace_name) { 'custom_app' }
    let(:rails_version_major) { 7 }
    let(:rails_module) { Module.new }

    let(:application_class) { double('custom rails class', module_parent_name: namespace_name) }

    let(:application) { double('custom rails', class: application_class) }

    before do
      rails_version = Module.new
      rails_version.const_set(:MAJOR, rails_version_major)
      rails_module.const_set(:VERSION, rails_version)
      rails_module.define_singleton_method(:application) { application }
      allow(rails_module).to receive(:application).and_return(application)
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
