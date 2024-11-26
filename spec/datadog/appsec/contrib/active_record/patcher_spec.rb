# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/active_record/patcher'

RSpec.describe Datadog::AppSec::Contrib::ActiveRecord::Patcher do
  describe '#prepended_class_name' do
    context 'when ActiveRecord version is 7.1 or higher' do
      before do
        stub_const(
          '::ActiveRecord',
          Module.new do
            module_function def gem_version
              Gem::Version.new('7.1')
            end
          end
        )
      end

      it 'returns Instrumentation::InternalExecQueryAdapterPatch' do
        expect(described_class.prepended_class_name(:postgresql)).to eq(
          Datadog::AppSec::Contrib::ActiveRecord::Instrumentation::InternalExecQueryAdapterPatch
        )
      end
    end

    context 'when ActiveRecord version is lower than 7.1' do
      before do
        stub_const(
          '::ActiveRecord',
          Module.new do
            module_function def gem_version
              Gem::Version.new('7.0')
            end
          end
        )
      end

      context 'for postgresql adapter' do
        context 'when ActiveRecord::ConnectionAdapters::JdbcAdapter is defined' do
          before do
            stub_const('::ActiveRecord::ConnectionAdapters::JdbcAdapter', Class.new)
          end

          it 'returns Instrumentation::ExecQueryAdapterPatch' do
            expect(described_class.prepended_class_name(:postgresql)).to eq(
              Datadog::AppSec::Contrib::ActiveRecord::Instrumentation::ExecQueryAdapterPatch
            )
          end
        end

        it 'returns Instrumentation::ExecuteAndClearAdapterPatch' do
          expect(described_class.prepended_class_name(:postgresql)).to eq(
            Datadog::AppSec::Contrib::ActiveRecord::Instrumentation::ExecuteAndClearAdapterPatch
          )
        end
      end

      %i[mysql2 sqlite3].each do |adapter_name|
        context "for #{adapter_name} adapter" do
          it 'returns Instrumentation::ExecQueryAdapterPatch' do
            expect(described_class.prepended_class_name(adapter_name)).to eq(
              Datadog::AppSec::Contrib::ActiveRecord::Instrumentation::ExecQueryAdapterPatch
            )
          end
        end
      end
    end
  end
end
