require 'datadog/tracing/contrib/rails/rails_helper'
require "datadog/di/spec_helper"
require 'datadog/di'
require 'datadog/di/probe_file_loader'

RSpec.describe Datadog::DI::ProbeFileLoader do
  di_test

  let(:loader) { described_class }

  describe '.load_now_or_later' do
    context 'in rails app' do
      before do
        expect(Datadog::Core::Contrib::Rails::Utils.railtie_supported?).to be true
      end

      it 'calls load_now when application is initialized' do
        RSpec::Mocks.with_temporary_scope do
          expect(described_class).not_to receive(:load_now)
          described_class.load_now_or_later
        end

        app = Class.new(Rails::Application) do
          config.eager_load = false
          config.active_support.to_time_preserves_timezone = :zone

          # globalid requires this, is there a better way to have the
          # railtie_name be set to a non-empty string?
          define_method(:railtie_name) { 'test-app' }
        end

        RSpec::Mocks.with_temporary_scope do
          expect(described_class).to receive(:load_now)
          app.initialize!
        end

        expect(Rails.application).to be_a(Rails::Application)
      end
    end
  end
end
