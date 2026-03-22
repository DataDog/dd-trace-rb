# frozen_string_literal: true

require 'spec_helper'
require 'datadog/symbol_database/component'

RSpec.describe 'Symbol Database Minimal' do
  # Create test class in temp directory (not /spec to pass user_code_path? filter)
  before(:all) do
    @test_app_dir = Dir.mktmpdir('symbol_db_test_app')
    @test_app_file = File.join(@test_app_dir, 'user_test_app.rb')
    File.write(@test_app_file, <<~RUBY)
      module UserTestApp
        class UserClass
          CONSTANT = 42

          def user_method(arg1, arg2)
            arg1 + arg2
          end

          def self.class_method
            'result'
          end
        end
      end
    RUBY
    require @test_app_file
  end

  after(:all) do
    FileUtils.remove_entry(@test_app_dir) if @test_app_dir && File.exist?(@test_app_dir)
  end

  it 'manually tests upload flow' do
    uploaded_scopes = []

    # Spy on upload
    allow_any_instance_of(Datadog::SymbolDatabase::Uploader).to receive(:upload_scopes) do |_uploader, scopes|
      puts "UPLOAD CALLED: #{scopes.length} scopes"
      uploaded_scopes.concat(scopes)
    end

    settings = Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.symbol_database.internal.force_upload = true
      s.remote.enabled = false
      s.service = 'rspec'
      s.env = 'test'
      s.version = '1.0.0'
      s.agent.host = 'localhost'
      s.agent.port = 8126
    end

    agent_settings = Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
    logger = Logger.new($stdout)

    # Build component with remote config enabled (don't use force upload to control timing)
    settings.remote.enabled = true
    settings.symbol_database.internal.force_upload = false
    component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger)

    # Manually call start_upload (runs synchronously)
    puts "Calling start_upload..."
    component.start_upload

    # Upload happens synchronously in start_upload, so check immediately
    puts "Uploaded scopes: #{uploaded_scopes.length}"
    puts "Scope names: #{uploaded_scopes.map(&:name).join(', ')}"

    # Verify we got our test class
    user_class_scope = uploaded_scopes.find { |s| s.name == 'UserTestApp::UserClass' }
    puts "Found UserTestApp::UserClass: #{!user_class_scope.nil?}"

    # Verify NO Datadog::* classes
    datadog_scopes = uploaded_scopes.select { |s| s.name&.start_with?('Datadog::') }
    puts "Datadog scopes (should be 0): #{datadog_scopes.length}"

    component.shutdown!

    expect(uploaded_scopes).not_to be_empty
    expect(user_class_scope).not_to be_nil
    expect(datadog_scopes).to be_empty
  end
end
