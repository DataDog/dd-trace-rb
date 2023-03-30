require 'datadog/tracing/contrib/action_pack/configuration/settings'

RSpec.describe Datadog::Tracing::Contrib::ActionPack::Configuration::Settings do
  describe 'Option `exception_controller`' do
    context 'when without defining option' do
      it { expect { described_class.new }.not_to log_deprecation }
    end

    context 'when given a non `nil` value' do
      it do
        expect { described_class.new(exception_controller: '123') }
          .to log_deprecation(include('Option `exception_controller` is no longer required'))
      end

      it do
        expect { described_class.new.tap { |s| s.exception_controller = '123' } }
          .to log_deprecation(include('Option `exception_controller` is no longer required'))
      end
    end
  end
end
