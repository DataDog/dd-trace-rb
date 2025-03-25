# frozen_string_literal: true

require 'tempfile'

RSpec.describe Datadog::Tracing::Contrib::Support do
  describe '.autoloaded?' do
    let(:temp_file) do
      file = Tempfile.create(['autoloaded_constant', '.rb'])
      file.write('module AutoloadedParent::AutoloadedConstant; end')
      file.flush
      file
    end
    let(:test_module) do
      temp_file = self.temp_file
      stub_const(
        'AutoloadedParent',
        Module.new do
          autoload :AutoloadedConstant, temp_file.path
          const_set(:LoadedConstant, Class.new)
        end
      )
    end

    after { temp_file.close }

    it 'returns false for autoloaded but not yet loaded constants' do
      expect(described_class.autoloaded?(test_module, :AutoloadedConstant)).to be false
    end

    it 'returns true for autoloaded and loaded constants' do
      test_module::AutoloadedConstant # rubocop:disable Lint/Void
      expect(described_class.autoloaded?(test_module, :AutoloadedConstant)).to be true
    end

    it 'returns true for loaded constants' do
      expect(described_class.autoloaded?(test_module, :LoadedConstant)).to be true
    end

    it 'returns false for undefined constants' do
      expect(described_class.autoloaded?(test_module, :UndefinedConstant)).to be false
    end
  end
end
