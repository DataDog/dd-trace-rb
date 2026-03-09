# frozen_string_literal: true

require 'datadog/symbol_database/extractor'
require 'fileutils'

RSpec.describe Datadog::SymbolDatabase::Extractor do
  # Helper to create test files in user code location
  def create_user_code_file(content)
    Dir.mkdir('/tmp/user_app') unless Dir.exist?('/tmp/user_app')
    filename = "/tmp/user_app/test_#{Time.now.to_i}_#{rand(10000)}.rb"
    File.write(filename, content)
    filename
  end

  def cleanup_user_code_file(filename)
    File.unlink(filename) if File.exist?(filename)
  end

  describe '.extract' do
    it 'returns nil for non-Module input' do
      expect(described_class.extract("not a module")).to be_nil
      expect(described_class.extract(42)).to be_nil
      expect(described_class.extract(nil)).to be_nil
    end

    it 'returns nil for anonymous module' do
      anonymous_mod = Module.new
      expect(described_class.extract(anonymous_mod)).to be_nil
    end

    it 'returns nil for anonymous class' do
      anonymous_class = Class.new
      expect(described_class.extract(anonymous_class)).to be_nil
    end

    context 'with gem code' do
      it 'returns nil for RSpec module (gem code)' do
        expect(described_class.extract(RSpec)).to be_nil
      end
    end

    context 'with stdlib code' do
      it 'returns nil for File class (stdlib)' do
        expect(described_class.extract(File)).to be_nil
      end
    end

    context 'with user code module' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestUserModule
            SOME_CONSTANT = 42

            def self.module_method
              "result"
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestUserModule) if defined?(TestUserModule)
        cleanup_user_code_file(@filename)
      end

      it 'extracts MODULE scope for user code module' do
        scope = described_class.extract(TestUserModule)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('MODULE')
        expect(scope.name).to eq('TestUserModule')
        expect(scope.source_file).to eq(@filename)
      end

      it 'includes file hash in language_specifics' do
        scope = described_class.extract(TestUserModule)

        expect(scope.language_specifics).to have_key(:file_hash)
        expect(scope.language_specifics[:file_hash]).to be_a(String)
        expect(scope.language_specifics[:file_hash].length).to eq(40)
      end

      it 'extracts module-level constants' do
        scope = described_class.extract(TestUserModule)

        constant_symbol = scope.symbols.find { |s| s.name == 'SOME_CONSTANT' }
        expect(constant_symbol).not_to be_nil
        expect(constant_symbol.symbol_type).to eq('STATIC_FIELD')
      end
    end

    context 'with user code class' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestUserClass
            CONSTANT = "value"
            @@class_var = 123

            def public_method(arg1, arg2 = nil)
              arg1 + arg2.to_s
            end

            private

            def private_method
              "private"
            end

            def self.class_method(param)
              param * 2
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestUserClass) if defined?(TestUserClass)
        cleanup_user_code_file(@filename)
      end

      it 'extracts CLASS scope for user code class' do
        scope = described_class.extract(TestUserClass)

        expect(scope).not_to be_nil
        expect(scope.scope_type).to eq('CLASS')
        expect(scope.name).to eq('TestUserClass')
        expect(scope.source_file).to eq(@filename)
      end

      it 'extracts class variables' do
        scope = described_class.extract(TestUserClass)

        class_var = scope.symbols.find { |s| s.name == '@@class_var' }
        expect(class_var).not_to be_nil
        expect(class_var.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts constants' do
        scope = described_class.extract(TestUserClass)

        constant = scope.symbols.find { |s| s.name == 'CONSTANT' }
        expect(constant).not_to be_nil
        expect(constant.symbol_type).to eq('STATIC_FIELD')
      end

      it 'extracts instance methods as METHOD scopes' do
        scope = described_class.extract(TestUserClass)

        method_scopes = scope.scopes.select { |s| s.scope_type == 'METHOD' }
        method_names = method_scopes.map(&:name)

        expect(method_names).to include('public_method')
        expect(method_names).to include('private_method')
      end

      it 'extracts class methods as METHOD scopes' do
        scope = described_class.extract(TestUserClass)

        class_method = scope.scopes.find { |s| s.name == 'self.class_method' }
        expect(class_method).not_to be_nil
        expect(class_method.scope_type).to eq('METHOD')
      end

      it 'captures method visibility' do
        scope = described_class.extract(TestUserClass)

        public_method = scope.scopes.find { |s| s.name == 'public_method' }
        expect(public_method.language_specifics[:visibility]).to eq('public')

        private_method = scope.scopes.find { |s| s.name == 'private_method' }
        expect(private_method.language_specifics[:visibility]).to eq('private')
      end

      it 'extracts method parameters' do
        scope = described_class.extract(TestUserClass)

        method_scope = scope.scopes.find { |s| s.name == 'public_method' }

        arg1 = method_scope.symbols.find { |s| s.name == 'arg1' }
        expect(arg1).not_to be_nil
        expect(arg1.symbol_type).to eq('ARG')

        arg2 = method_scope.symbols.find { |s| s.name == 'arg2' }
        expect(arg2).not_to be_nil
        expect(arg2.symbol_type).to eq('ARG')
      end
    end

    context 'with class inheritance' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          class TestBaseClass
            def base_method
            end
          end

          class TestDerivedClass < TestBaseClass
            def derived_method
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestDerivedClass) if defined?(TestDerivedClass)
        Object.send(:remove_const, :TestBaseClass) if defined?(TestBaseClass)
        cleanup_user_code_file(@filename)
      end

      it 'captures superclass in language_specifics' do
        scope = described_class.extract(TestDerivedClass)

        expect(scope.language_specifics[:superclass]).to eq('TestBaseClass')
      end

      it 'excludes Object from superclass' do
        scope = described_class.extract(TestBaseClass)

        expect(scope.language_specifics).not_to have_key(:superclass)
      end
    end

    context 'with mixins' do
      before do
        @filename = create_user_code_file(<<~RUBY)
          module TestMixin
          end

          class TestClassWithMixin
            include TestMixin

            def test_method
            end
          end
        RUBY
        load @filename
      end

      after do
        Object.send(:remove_const, :TestClassWithMixin) if defined?(TestClassWithMixin)
        Object.send(:remove_const, :TestMixin) if defined?(TestMixin)
        cleanup_user_code_file(@filename)
      end

      it 'captures included modules in language_specifics' do
        scope = described_class.extract(TestClassWithMixin)

        expect(scope.language_specifics[:included_modules]).to include('TestMixin')
      end
    end
  end

  describe '.user_code_path?' do
    it 'returns false for gem paths' do
      expect(described_class.send(:user_code_path?, '/path/to/gems/rspec/lib/rspec.rb')).to be false
    end

    it 'returns false for ruby stdlib paths' do
      expect(described_class.send(:user_code_path?, '/usr/lib/ruby/3.2/pathname.rb')).to be false
    end

    it 'returns false for internal paths' do
      expect(described_class.send(:user_code_path?, '<internal:array>')).to be false
    end

    it 'returns false for eval paths' do
      expect(described_class.send(:user_code_path?, '(eval):1')).to be false
    end

    it 'returns false for spec paths' do
      expect(described_class.send(:user_code_path?, '/project/spec/my_spec.rb')).to be false
    end

    it 'returns true for user code paths' do
      expect(described_class.send(:user_code_path?, '/app/lib/my_class.rb')).to be true
      expect(described_class.send(:user_code_path?, '/home/user/project/file.rb')).to be true
      expect(described_class.send(:user_code_path?, '/tmp/user_app/test.rb')).to be true
    end
  end

  describe '.find_source_file' do
    before do
      @filename = create_user_code_file(<<~RUBY)
        class TestClassForSourceFile
          def test_method
          end
        end
      RUBY
      load @filename
    end

    after do
      Object.send(:remove_const, :TestClassForSourceFile) if defined?(TestClassForSourceFile)
      cleanup_user_code_file(@filename)
    end

    it 'finds source file from instance methods' do
      source_file = described_class.send(:find_source_file, TestClassForSourceFile)
      expect(source_file).to eq(@filename)
    end

    it 'returns nil for modules without methods' do
      empty_mod = Module.new

      source_file = described_class.send(:find_source_file, empty_mod)
      expect(source_file).to be_nil
    end
  end
end
