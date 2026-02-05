# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/configuration'

RSpec.describe Datadog::OpenFeature::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'open_feature' do
    describe '#enabled' do
      subject(:enabled) { settings.open_feature.enabled }

      context 'when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is not defined' do
        with_env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED' => nil

        it { expect(enabled).to be(false) }
      end

      context 'when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is defined as true' do
        with_env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED' => 'true'

        it { expect(enabled).to be(true) }
      end

      context 'when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is defined as false' do
        with_env 'DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED' => 'false'

        it { expect(enabled).to be(false) }
      end
    end

    describe '#enabled=' do
      context 'when set to true' do
        before { settings.open_feature.enabled = true }

        it { expect(settings.open_feature.enabled).to be(true) }
      end

      context 'when set to false' do
        before { settings.open_feature.enabled = false }

        it { expect(settings.open_feature.enabled).to be(false) }
      end
    end
  end
end
