# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/configuration/settings'

RSpec.describe 'Symbol Database Configuration' do
  describe 'DD_SYMBOL_DATABASE_UPLOAD_ENABLED' do
    context 'when not set' do
      it 'defaults to true' do
        settings = Datadog::Core::Configuration::Settings.new
        expect(settings.symbol_database.enabled).to be true
      end
    end
  end

  describe 'DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD' do
    context 'when not set' do
      it 'defaults to false' do
        settings = Datadog::Core::Configuration::Settings.new
        expect(settings.symbol_database.internal.force_upload).to be false
      end
    end
  end

  # Configuration accessors must be safe on all platforms — the platform guard lives in
  # Component.build, not in the settings layer. Reading these settings must never raise
  # regardless of Ruby engine or version.
  describe 'config accessibility on any platform', :symdb_supported_platforms do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    it 'enabled is readable' do
      expect { settings.symbol_database.enabled }.not_to raise_error
    end

    it 'internal.force_upload is readable' do
      expect { settings.symbol_database.internal.force_upload }.not_to raise_error
    end

    it 'enabled is writable' do
      expect { settings.symbol_database.enabled = false }.not_to raise_error
    end
  end
end
