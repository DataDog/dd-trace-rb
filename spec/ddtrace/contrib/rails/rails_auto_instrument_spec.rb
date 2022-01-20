# typed: false
require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Datadog::Contrib::AutoInstrument' do
  include_context 'Rails test application'

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    without_warnings { Datadog::Tracing.configuration.reset! }

    ClimateControl.modify('TEST_AUTO_INSTRUMENT' => 'true') do
      example.run
    end

    without_warnings { Datadog::Tracing.configuration.reset! }
  end

  context 'when auto patching is included' do
    before do
      skip 'Fork not supported on current platform' unless Process.respond_to?(:fork)
    end

    let(:config) { Datadog::Tracing.configuration[:rails] }

    it 'configurations application correctly' do
      expect_in_fork do
        app

        expect(config[:template_base_path]).to eq('views/')
      end
    end

    it 'sets default database' do
      expect_in_fork do
        app
        expect(adapter_name).not_to eq('defaultdb')
      end
    end
  end
end
