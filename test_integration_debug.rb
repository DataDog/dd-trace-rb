#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'datadog'
require 'datadog/symbol_database/component'
require 'datadog/symbol_database/remote'
require 'datadog/core/remote/configuration/repository'
require 'digest'
require 'webrick'
require 'json'
require 'zlib'

# Create test class
module TestModule
  class TestClass
    def test_method(arg1, arg2)
      arg1 + arg2
    end
  end
end

# Track uploaded payloads
$uploaded_payloads = []

# Start test HTTP server
server = WEBrick::HTTPServer.new(Port: 8126, AccessLog: [], Logger: WEBrick::Log.new("/dev/null"))
server.mount_proc('/symdb/v1/input') do |req, res|
  puts "=== UPLOAD REQUEST RECEIVED ==="
  puts "Path: #{req.path}"
  puts "Content-Type: #{req.content_type}"

  # Try to extract payload
  body = req.body
  if body =~ /Content-Disposition: form-data; name="file".*?\r\n\r\n(.+?)\r\n----/m ||
      body =~ /Content-Disposition: form-data; name="file".*?\n\n(.+?)\n----/m
    gzipped_data = $1
    json_string = Zlib::GzipReader.new(StringIO.new(gzipped_data)).read
    payload = JSON.parse(json_string)
    $uploaded_payloads << payload
    puts "Payload received: #{payload.keys}"
    puts "Scopes count: #{payload['scopes']&.length}"
  end

  res.status = 200
  res.body = '{}'
end

# Start server in background
Thread.new { server.start }
sleep 0.5

# Configure Datadog
puts "=== Configuring Datadog ==="
settings = Datadog::Core::Configuration::Settings.new
settings.symbol_database.enabled = true
settings.remote.enabled = true
settings.service = 'test'
settings.env = 'test'
settings.version = '1.0.0'
settings.agent.host = 'localhost'
settings.agent.port = 8126

agent_settings = Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)

logger = Logger.new(STDOUT)
logger.level = Logger::DEBUG

# Set Datadog logger to our logger so we can see debug messages
Datadog.configure do |c|
  c.logger.instance = logger
end

# Build component
puts "=== Building Component ==="
component = Datadog::SymbolDatabase::Component.build(settings, agent_settings, logger, telemetry: nil)
puts "Component built: #{component ? 'YES' : 'NO'}"

# Mock Datadog.send(:components) - manually monkey-patch for testing
module Datadog
  class << self
    alias_method :original_send, :send

    def send(method_name, *args)
      if method_name == :components
        $test_components
      else
        original_send(method_name, *args)
      end
    end
  end
end

components = Struct.new(:symbol_database).new(component)
$test_components = components

# Create repository and receiver
puts "=== Setting up Remote Config ==="
repository = Datadog::Core::Remote::Configuration::Repository.new
receiver = Datadog::SymbolDatabase::Remote.receivers(nil)[0]

# Simulate remote config insert
puts "=== Simulating Remote Config Insert ==="
config_path = 'datadog/2/LIVE_DEBUGGING_SYMBOL_DB/test/config'
content_json = {upload_symbols: true}.to_json

target = Datadog::Core::Remote::Configuration::Target.parse(
  {
    'custom' => {'v' => 1},
    'hashes' => {'sha256' => Digest::SHA256.hexdigest(content_json)},
    'length' => content_json.length,
  }
)

rc_content = Datadog::Core::Remote::Configuration::Content.parse(
  {
    path: config_path,
    content: content_json,
  }
)

changes = repository.transaction do |_repository, transaction|
  transaction.insert(rc_content.path, target, rc_content)
end

puts "Changes count: #{changes.length}"
changes.each { |ch| puts "  - #{ch.type} for #{ch.content.path}" }

# Test that our monkey-patch works
puts "Testing components access:"
test_components = Datadog.send(:components)
puts "  Datadog.send(:components): #{test_components ? 'YES' : 'NO'}"
puts "  Datadog.send(:components).symbol_database: #{test_components&.symbol_database ? 'YES' : 'NO'}"

puts "Calling receiver..."
receiver.call(repository, changes)

# Wait for upload
puts "=== Waiting for upload ==="
sleep 2

puts "=== Results ==="
puts "Uploaded payloads count: #{$uploaded_payloads.length}"
if $uploaded_payloads.any?
  puts "First payload scopes: #{$uploaded_payloads.first['scopes']&.length}"
else
  puts "NO UPLOADS RECEIVED!"
end

server.shutdown
