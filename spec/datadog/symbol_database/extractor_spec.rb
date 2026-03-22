# frozen_string_literal: true

require 'datadog/symbol_database/extractor'

# Test class defined in-process for extraction testing
module SymbolDatabaseTestApp
  class TestController
    def index(page, per_page:)
      page.to_s
    end

    def show(id)
      id
    end

    private

    def authorize
      true
    end
  end

  class BaseModel
    def save
      true
    end
  end

  class User < BaseModel
    def name
      'test'
    end
  end
end

RSpec.describe Datadog::SymbolDatabase::Extractor do
  let(:settings) do
    s = double('settings')
    sd = double('symbol_database')
    allow(sd).to receive(:includes).and_return([])
    allow(s).to receive(:symbol_database).and_return(sd)
    s
  end
  let(:logger) { double('logger', debug: nil).tap { |l| allow(l).to receive(:debug).and_yield } }
  let(:extractor) { described_class.new(settings, logger) }

  describe '#extract' do
    it 'returns an array of MODULE scopes' do
      scopes = extractor.extract
      expect(scopes).to be_an(Array)
      scopes.each do |scope|
        expect(scope.scope_type).to eq('MODULE')
      end
    end

    it 'excludes gem and stdlib classes' do
      scopes = extractor.extract
      all_class_names = scopes.flat_map { |m| (m.scopes || []).map(&:name) }
      expect(all_class_names).not_to include('String')
      expect(all_class_names).not_to include('Array')
      expect(all_class_names).not_to include('Hash')
    end

    it 'excludes Datadog namespace' do
      scopes = extractor.extract
      all_class_names = scopes.flat_map { |m| (m.scopes || []).map(&:name) }
      datadog_classes = all_class_names.select { |n| n&.start_with?('Datadog') }
      expect(datadog_classes).to be_empty
    end
  end

  describe '#extract_class (via send)' do
    let(:source_file) { SymbolDatabaseTestApp::TestController.instance_method(:index).source_location[0] }

    it 'extracts method scopes from a class' do
      scope = extractor.send(:extract_class, SymbolDatabaseTestApp::TestController, source_file)
      expect(scope).not_to be_nil
      expect(scope.scope_type).to eq('CLASS')
      expect(scope.name).to eq('SymbolDatabaseTestApp::TestController')
      method_names = scope.scopes.map(&:name)
      expect(method_names).to include('index')
      expect(method_names).to include('show')
      expect(method_names).to include('authorize')
    end

    it 'extracts method parameters as ARG symbols' do
      scope = extractor.send(:extract_class, SymbolDatabaseTestApp::TestController, source_file)
      index_method = scope.scopes.find { |m| m.name == 'index' }
      expect(index_method).not_to be_nil
      arg_names = index_method.symbols.map(&:name)
      expect(arg_names).to include('page')
      expect(arg_names).to include('per_page')
    end

    it 'extracts method visibility' do
      scope = extractor.send(:extract_class, SymbolDatabaseTestApp::TestController, source_file)
      public_method = scope.scopes.find { |m| m.name == 'index' }
      expect(public_method.language_specifics[:access_modifiers]).to eq(['public'])

      private_method = scope.scopes.find { |m| m.name == 'authorize' }
      expect(private_method.language_specifics[:access_modifiers]).to eq(['private'])
    end

    it 'extracts superclass' do
      user_file = SymbolDatabaseTestApp::User.instance_method(:name).source_location[0]
      scope = extractor.send(:extract_class, SymbolDatabaseTestApp::User, user_file)
      expect(scope.language_specifics[:super_classes]).to eq(['SymbolDatabaseTestApp::BaseModel'])
    end
  end

  describe '#compute_file_hash (via send)' do
    it 'computes a valid git-style SHA-1 hash' do
      # Create a temp file with known content
      require 'tempfile'
      tmpfile = Tempfile.new(['test', '.rb'])
      tmpfile.write("puts 'hello'\n")
      tmpfile.close

      hash = extractor.send(:compute_file_hash, tmpfile.path)
      expect(hash).to match(/\A[0-9a-f]{40}\z/)

      # Verify against expected: "blob 14\0puts 'hello'\n"
      content = File.binread(tmpfile.path)
      expected = Digest::SHA1.hexdigest("blob #{content.bytesize}\0#{content}")
      expect(hash).to eq(expected)

      tmpfile.unlink
    end

    it 'returns nil for non-existent file' do
      hash = extractor.send(:compute_file_hash, '/nonexistent/file.rb')
      expect(hash).to be_nil
    end
  end

  describe '#user_code_path? (via send)' do
    it 'accepts absolute .rb paths not in gems or stdlib' do
      expect(extractor.send(:user_code_path?, '/app/models/user.rb')).to be true
    end

    it 'rejects nil' do
      expect(extractor.send(:user_code_path?, nil)).to be false
    end

    it 'rejects non-.rb files' do
      expect(extractor.send(:user_code_path?, '/app/lib/thing.so')).to be false
    end

    it 'rejects relative paths' do
      expect(extractor.send(:user_code_path?, 'app/models/user.rb')).to be false
    end

    it 'rejects Datadog tracer paths' do
      tracer_path = extractor.instance_variable_get(:@tracer_path)
      expect(extractor.send(:user_code_path?, "#{tracer_path}/lib/datadog/something.rb")).to be false
    end
  end
end
