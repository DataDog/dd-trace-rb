# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'

RSpec.describe 'Symbol Database Debug' do
  let(:logger) { Logger.new($stdout) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.symbol_database.force_upload = true
      s.remote.enabled = false
      s.service = 'rspec'
      s.env = 'test'
      s.version = '1.0.0'
      s.agent.host = 'localhost'
      s.agent.port = 8126  # Use standard port for now
    end
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end

  it 'builds component and triggers upload' do
    # Spy on multiple methods to trace the flow
    upload_called = false
    flush_called = false
    perform_upload_called = false
    extracted_scopes = []

    allow_any_instance_of(Datadog::SymbolDatabase::Uploader).to receive(:upload_scopes) do |_uploader, scopes|
      puts "=== UPLOAD CALLED ==="
      puts "Scopes count: #{scopes.length}"
      puts "First scope: #{scopes.first&.name}"
      upload_called = true
    end

    allow_any_instance_of(Datadog::SymbolDatabase::ScopeContext).to receive(:flush).and_wrap_original do |original_method, *args|
      puts "=== FLUSH CALLED ==="
      flush_called = true
      original_method.call(*args)
    end

    allow_any_instance_of(Datadog::SymbolDatabase::ScopeContext).to receive(:perform_upload).and_wrap_original do |original_method, scopes|
      puts "=== PERFORM_UPLOAD CALLED ==="
      puts "Scopes nil: #{scopes.nil?}"
      puts "Scopes empty: #{scopes&.empty?}"
      puts "Scopes count: #{scopes&.length}"
      perform_upload_called = true
      original_method.call(scopes)
    end

    added_scopes = []
    rejected_scopes = []

    allow_any_instance_of(Datadog::SymbolDatabase::ScopeContext).to receive(:add_scope).and_wrap_original do |original_method, scope|
      extracted_scopes << scope.name if scope

      # Check if it will be added or rejected
      context = original_method.receiver
      if context.instance_variable_get(:@uploaded_modules).include?(scope.name)
        rejected_scopes << scope.name
      else
        added_scopes << scope.name
      end

      original_method.call(scope)
    end

    component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger)

    puts "Component built: #{!component.nil?}"
    puts "Waiting for extraction and upload..."

    # Wait for extraction + timer
    sleep 3

    # Check internal state
    scope_context = component.instance_variable_get(:@scope_context)
    scopes_in_context = scope_context.instance_variable_get(:@scopes)

    puts "Extracted scopes count: #{extracted_scopes.length}"
    puts "Added scopes count: #{added_scopes.length}"
    puts "Rejected scopes count: #{rejected_scopes.length}"
    puts "@scopes.size in context: #{scopes_in_context.size}"
    puts "First 5 extracted: #{extracted_scopes.first(5).join(', ')}"
    puts "Flush called: #{flush_called}"
    puts "Upload called: #{upload_called}"

    component&.shutdown!

    expect(flush_called).to be true
    expect(upload_called).to be true
  end
end
