# frozen_string_literal: true

# Tests ported from Python dd-trace-py:
#   tests/internal/symbol_db/test_config.py::test_symbol_db_includes_pattern
#
# Python tests that DD_SYMBOL_DATABASE_INCLUDES=foo,bar creates a regex that:
#   - Matches "foo", "bar", "foo.baz" (prefix match with dot separator)
#   - Does NOT match "baz", "baz.foo", "foobar"
#
# Ruby equivalent: settings.symbol_database.includes parses comma-separated
# env var into an array. The Ruby implementation doesn't use regex for matching
# (it stores an array), so this test validates the parsing behavior.

require 'spec_helper'
require 'datadog/symbol_database/configuration/settings'

RSpec.describe 'Symbol Database Configuration' do
  describe 'DD_SYMBOL_DATABASE_INCLUDES parsing' do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    context 'with comma-separated values' do
      around do |example|
        ClimateControl.modify('DD_SYMBOL_DATABASE_INCLUDES' => 'foo,bar') do
          example.run
        end
      end

      it 'parses includes into an array' do
        fresh_settings = Datadog::Core::Configuration::Settings.new
        includes = fresh_settings.symbol_database.includes

        expect(includes).to be_an(Array)
        expect(includes).to include('foo')
        expect(includes).to include('bar')
      end

      it 'does not include unspecified modules' do
        fresh_settings = Datadog::Core::Configuration::Settings.new
        includes = fresh_settings.symbol_database.includes

        expect(includes).not_to include('baz')
      end
    end

    context 'with whitespace around values' do
      around do |example|
        ClimateControl.modify('DD_SYMBOL_DATABASE_INCLUDES' => ' foo , bar ') do
          example.run
        end
      end

      it 'strips whitespace from values' do
        fresh_settings = Datadog::Core::Configuration::Settings.new
        includes = fresh_settings.symbol_database.includes

        expect(includes).to include('foo')
        expect(includes).to include('bar')
        expect(includes).not_to include(' foo ')
        expect(includes).not_to include(' bar ')
      end
    end

    context 'with empty value' do
      around do |example|
        ClimateControl.modify('DD_SYMBOL_DATABASE_INCLUDES' => '') do
          example.run
        end
      end

      it 'returns empty array' do
        fresh_settings = Datadog::Core::Configuration::Settings.new
        includes = fresh_settings.symbol_database.includes

        expect(includes).to be_an(Array)
        expect(includes).to be_empty
      end
    end

    context 'without env var set' do
      it 'defaults to empty array' do
        includes = settings.symbol_database.includes

        expect(includes).to eq([])
      end
    end

    context 'with single value' do
      around do |example|
        ClimateControl.modify('DD_SYMBOL_DATABASE_INCLUDES' => 'my_app') do
          example.run
        end
      end

      it 'parses single value into array' do
        fresh_settings = Datadog::Core::Configuration::Settings.new
        includes = fresh_settings.symbol_database.includes

        expect(includes).to eq(['my_app'])
      end
    end

    context 'programmatic setting' do
      it 'accepts array directly' do
        settings.symbol_database.includes = ['App::Models', 'App::Services']

        expect(settings.symbol_database.includes).to eq(['App::Models', 'App::Services'])
      end
    end
  end

  describe 'DD_SYMBOL_DATABASE_UPLOAD_ENABLED' do
    context 'when not set' do
      it 'defaults to true' do
        settings = Datadog::Core::Configuration::Settings.new
        expect(settings.symbol_database.enabled).to be true
      end
    end
  end

  describe 'DD_SYMBOL_DATABASE_FORCE_UPLOAD' do
    context 'when not set' do
      it 'defaults to false' do
        settings = Datadog::Core::Configuration::Settings.new
        expect(settings.symbol_database.force_upload).to be false
      end
    end
  end

  # NOTE: symbol_database.internal.upload_class_methods is a code-only internal setting
  # (no env var). It is exercised indirectly by extractor_spec.rb tests that pass
  # upload_class_methods: true.

  # Configuration accessors must be safe on all platforms — the platform guard lives in
  # Component.build, not in the settings layer. Reading these settings must never raise
  # regardless of Ruby engine or version.
  describe 'config accessibility on any platform', :symdb_supported_platforms do
    let(:settings) { Datadog::Core::Configuration::Settings.new }

    it 'enabled is readable' do
      expect { settings.symbol_database.enabled }.not_to raise_error
    end

    it 'force_upload is readable' do
      expect { settings.symbol_database.force_upload }.not_to raise_error
    end

    it 'includes is readable' do
      expect { settings.symbol_database.includes }.not_to raise_error
    end

    it 'internal.upload_class_methods is readable' do
      expect { settings.symbol_database.internal.upload_class_methods }.not_to raise_error
    end

    it 'enabled is writable' do
      expect { settings.symbol_database.enabled = false }.not_to raise_error
    end

    it 'includes is writable' do
      expect { settings.symbol_database.includes = ['App::Models'] }.not_to raise_error
    end
  end
end
