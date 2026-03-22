# frozen_string_literal: true

require 'datadog'

RSpec.describe Datadog::SymbolDatabase::Configuration::Settings do
  around do |example|
    ClimateControl.modify(
      'DD_SYMBOL_DATABASE_UPLOAD_ENABLED' => nil,
      'DD_SYMBOL_DATABASE_FORCE_UPLOAD' => nil,
      'DD_SYMBOL_DATABASE_INCLUDES' => nil,
    ) do
      example.run
    end
  end

  describe 'symbol_database settings' do
    subject(:settings) do
      s = Datadog::Core::Configuration::Settings.new
      s
    end

    describe '#enabled' do
      it 'defaults to true' do
        expect(settings.symbol_database.enabled).to be true
      end

      context 'when DD_SYMBOL_DATABASE_UPLOAD_ENABLED is false' do
        around do |example|
          ClimateControl.modify('DD_SYMBOL_DATABASE_UPLOAD_ENABLED' => 'false') do
            example.run
          end
        end

        it 'returns false' do
          expect(settings.symbol_database.enabled).to be false
        end
      end
    end

    describe '#force_upload' do
      it 'defaults to false' do
        expect(settings.symbol_database.force_upload).to be false
      end

      context 'when DD_SYMBOL_DATABASE_FORCE_UPLOAD is true' do
        around do |example|
          ClimateControl.modify('DD_SYMBOL_DATABASE_FORCE_UPLOAD' => 'true') do
            example.run
          end
        end

        it 'returns true' do
          expect(settings.symbol_database.force_upload).to be true
        end
      end
    end

    describe '#includes' do
      it 'defaults to empty array' do
        expect(settings.symbol_database.includes).to eq([])
      end

      context 'when DD_SYMBOL_DATABASE_INCLUDES is set' do
        around do |example|
          ClimateControl.modify('DD_SYMBOL_DATABASE_INCLUDES' => 'MyApp, Lib::Core') do
            example.run
          end
        end

        it 'parses comma-separated values and strips whitespace' do
          expect(settings.symbol_database.includes).to eq(['MyApp', 'Lib::Core'])
        end
      end
    end
  end
end
