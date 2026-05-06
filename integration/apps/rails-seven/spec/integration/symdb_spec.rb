# frozen_string_literal: true

require 'spec_helper'
require 'json'

# Runs symbol database extraction inside the rails-seven process via `rails runner`.
# Exercises the real Rails environment — Zeitwerk autoloading, ActiveRecord method
# generation, gem path filtering — without needing a running web server or mock agent.
#
# Guards match di_spec.rb (JRuby and Ruby < 2.6 unsupported by symdb).
RSpec.describe 'Symbol database extraction' do
  di_test # reuse DI skip guards: JRuby and Ruby < 2.6 unsupported

  # Script executed inside the Rails process via `bin/rails runner`.
  # Force-loads all classes so ObjectSpace is fully populated before extraction.
  # rubocop:disable Lint/ConstantDefinitionInBlock
  EXTRACTION_SCRIPT = <<~RUBY
    require 'json'
    Rails.application.eager_load!

    extractor = Datadog::SymbolDatabase::Extractor.new(
      logger: Datadog.logger,
      settings: Datadog.configuration,
      telemetry: nil,
    )

    file_scopes = extractor.extract_all

    # Flatten to a list of { type:, name:, file:, method_names: [] } for easy assertion
    entries = file_scopes.flat_map do |file_scope|
      file_scope.scopes.map do |scope|
        {
          type: scope.scope_type,
          name: scope.name,
          file: file_scope.name,
          method_names: scope.scopes.select { |s| s.scope_type == 'METHOD' }.map(&:name),
        }
      end
    end

    print JSON.generate(entries)
  RUBY

  # rubocop:enable Lint/ConstantDefinitionInBlock

  let(:extraction_output) { `bin/rails runner '#{EXTRACTION_SCRIPT.tr("'", '"')}'` }
  let(:entries) { JSON.parse(extraction_output, symbolize_names: true) }

  # Helpers
  def find_class(name)
    entries.find { |e| e[:name] == name && e[:type] == 'CLASS' }
  end

  def find_module(name)
    entries.find { |e| e[:name] == name && e[:type] == 'MODULE' }
  end

  it 'produces at least one FILE scope' do
    expect(entries).not_to be_empty
  end

  describe 'DiController' do
    subject(:scope) { find_class('DiController') }

    it 'is extracted' do
      expect(scope).not_to be_nil
    end

    it 'has user-defined methods' do
      expect(scope[:method_names]).to include('ar_serializer')
    end

    it 'source file is in app/controllers' do
      expect(scope[:file]).to include('/app/controllers/')
    end
  end

  describe 'Test model (empty AR model)' do
    subject(:scope) { find_class('Test') }

    it 'is extracted even with no user-defined methods' do
      expect(scope).not_to be_nil
    end

    it 'source file is in app/models' do
      expect(scope[:file]).to include('/app/models/')
    end
  end

  describe 'ApplicationController' do
    subject(:scope) { find_class('ApplicationController') }

    it 'is extracted as empty CLASS on Ruby 2.7+',
      skip: (RUBY_VERSION < '2.7') ? 'const_source_location unavailable on Ruby 2.6' : false do
      expect(scope).not_to be_nil
    end
  end

  describe 'filtering' do
    it 'excludes Datadog:: namespace' do
      datadog_scopes = entries.select { |e| e[:name]&.start_with?('Datadog::') }
      expect(datadog_scopes).to be_empty
    end

    it 'excludes ActiveRecord::Base (gem code)' do
      expect(find_class('ActiveRecord::Base')).to be_nil
    end

    it 'excludes ActionController::Base (gem code)' do
      expect(find_class('ActionController::Base')).to be_nil
    end

    it 'produces no scope names with a leading dot' do
      leading_dot = entries.select { |e| e[:name]&.start_with?('.') }
      expect(leading_dot).to be_empty
    end
  end
end
