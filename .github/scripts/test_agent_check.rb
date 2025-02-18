#!/usr/bin/env ruby

require "net/http"
require "uri"
require "json"

# Disable exiting on command failure
agent_host = ENV["DD_AGENT_HOST"] || raise("DD_AGENT_HOST is not set")
agent_port = ENV["DD_TRACE_AGENT_PORT"] || raise("DD_TRACE_AGENT_PORT is not set")

begin
  # Check if test agent is running
  summary_uri = URI.parse("http://#{agent_host}:#{agent_port}/test/trace_check/summary")
  summary_response = Net::HTTP.get_response(summary_uri)

  if summary_response.code == "200"
    puts "APM Test Agent is running. (HTTP 200)"
  else
    puts "APM Test Agent is not running and was not used for testing. No checks failed."
    exit 0
  end

  # Check for test failures
  failures_uri = URI.parse("http://#{agent_host}:#{agent_port}/test/trace_check/failures")
  failures_response = Net::HTTP.get_response(failures_uri)

  case failures_response.code
  when "200"
    puts "All APM Test Agent Check Traces returned successful! (HTTP 200)"
    puts "APM Test Agent Check Traces Summary Results:"
    puts JSON.pretty_generate(JSON.parse(summary_response.body))
  when "404"
    puts "Real APM Agent running in place of TestAgent, no checks to validate!"
  else
    puts "APM Test Agent Check Traces failed with response code: #{failures_response.code}"
    puts "Failures:"
    puts failures_response.body
    puts "APM Test Agent Check Traces Summary Results:"
    puts JSON.pretty_generate(JSON.parse(summary_response.body))
    exit 1
  end
rescue => e
  puts "An error occurred: #{e.message}"
  exit 1
end
