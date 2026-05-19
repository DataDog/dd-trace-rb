# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/configuration'

# Configuration accessors must be safe on all platforms — the platform guard lives in
# Component.build, not in the settings layer. Reading these settings must never raise
# regardless of Ruby engine or version.
RSpec.describe 'Symbol Database Configuration', :symdb_supported_platforms do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'symbol_database' do
    context 'programmatic configuration' do
      [
        [nil, 'enabled', true],
        [nil, 'enabled', false],
        ['internal', 'force_upload', true],
        ['internal', 'force_upload', false],
        ['internal', 'trace_logging', true],
        ['internal', 'trace_logging', false],
      ].each do |(scope_name_, name_, value_)|
        scope_name = scope_name_
        name = name_
        value = value_

        context "when #{[scope_name, name].compact.join('.')} set to #{value}" do
          let(:scope) do
            if scope_name
              settings.symbol_database.public_send(scope_name)
            else
              settings.symbol_database
            end
          end

          before do
            scope.public_send("#{name}=", value)
          end

          it 'returns the value back' do
            expect(scope.public_send(name)).to eq(value)
          end
        end
      end
    end

    context 'environment variable configuration' do
      [
        ['DD_SYMBOL_DATABASE_UPLOAD_ENABLED', 'true', nil, 'enabled', true],
        ['DD_SYMBOL_DATABASE_UPLOAD_ENABLED', 'false', nil, 'enabled', false],
        ['DD_SYMBOL_DATABASE_UPLOAD_ENABLED', nil, nil, 'enabled', true],
        ['DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD', 'true', 'internal', 'force_upload', true],
        ['DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD', 'false', 'internal', 'force_upload', false],
        ['DD_INTERNAL_FORCE_SYMBOL_DATABASE_UPLOAD', nil, 'internal', 'force_upload', false],
        ['DD_TRACE_DEBUG', 'true', 'internal', 'trace_logging', true],
        ['DD_TRACE_DEBUG', 'false', 'internal', 'trace_logging', false],
        ['DD_TRACE_DEBUG', nil, 'internal', 'trace_logging', false],
      ].each do |(env_var_name_, env_var_value_, scope_name_, setting_name_, setting_value_)|
        env_var_name = env_var_name_
        env_var_value = env_var_value_
        scope_name = scope_name_
        setting_name = setting_name_
        setting_value = setting_value_

        context "when #{env_var_name}=#{env_var_value.inspect}" do
          around do |example|
            ClimateControl.modify(env_var_name => env_var_value) do
              example.run
            end
          end

          it "sets symbol_database.#{[scope_name, setting_name].compact.join('.')}=#{setting_value}" do
            scope = scope_name ? settings.symbol_database.public_send(scope_name) : settings.symbol_database
            expect(scope.public_send(setting_name)).to eq(setting_value)
          end
        end
      end
    end

    context 'config accessibility' do
      it 'enabled is readable' do
        expect { settings.symbol_database.enabled }.not_to raise_error
      end

      it 'internal.force_upload is readable' do
        expect { settings.symbol_database.internal.force_upload }.not_to raise_error
      end

      it 'internal.trace_logging is readable' do
        expect { settings.symbol_database.internal.trace_logging }.not_to raise_error
      end

      it 'enabled is writable' do
        expect { settings.symbol_database.enabled = false }.not_to raise_error
      end

      it 'internal.force_upload is writable' do
        expect { settings.symbol_database.internal.force_upload = true }.not_to raise_error
      end
    end
  end
end
