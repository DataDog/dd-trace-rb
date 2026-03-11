# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'

RSpec.describe 'Symbol Database Simple Debug' do
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
      s.agent.port = 8126
    end
  end

  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end

  it 'builds component and checks internal state' do
    upload_called = false
    perform_upload_args = []
    flush_calls = []

    # Spy on flush to see when/how it's called
    allow_any_instance_of(Datadog::SymbolDatabase::ScopeContext).to receive(:flush).and_wrap_original do |original_method, *args|
      context = original_method.receiver
      scopes_size = context.instance_variable_get(:@scopes).size
      puts "FLUSH called: @scopes.size=#{scopes_size}"
      flush_calls << scopes_size
      original_method.call(*args)
    end

    # Spy on perform_upload to see what's passed
    allow_any_instance_of(Datadog::SymbolDatabase::ScopeContext).to receive(:perform_upload).and_wrap_original do |original_method, scopes|
      puts "PERFORM_UPLOAD called: scopes=#{scopes.inspect[0..100]}"
      perform_upload_args << scopes
      original_method.call(scopes)
    end

    # Spy on the final upload method
    allow_any_instance_of(Datadog::SymbolDatabase::Uploader).to receive(:upload_scopes) do |_uploader, scopes|
      puts "UPLOAD CALLED with #{scopes.length} scopes"
      upload_called = true
    end

    component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger)

    puts "Component built"

    # Wait for extraction
    sleep 3

    # Check internal state WITHOUT any spies on add_scope
    scope_context = component.instance_variable_get(:@scope_context)
    scopes_array = scope_context.instance_variable_get(:@scopes)
    uploaded_modules = scope_context.instance_variable_get(:@uploaded_modules)

    puts "@scopes.size: #{scopes_array.size}"
    puts "@uploaded_modules.size: #{uploaded_modules.size}"
    puts "perform_upload called #{perform_upload_args.length} times"
    puts "perform_upload args: #{perform_upload_args.map { |a| a.nil? ? 'nil' : a.class.name + '(' + a.size.to_s + ')' }.join(', ')}"
    puts "Upload called: #{upload_called}"

    component.shutdown!

    expect(upload_called).to be true
  end
end
