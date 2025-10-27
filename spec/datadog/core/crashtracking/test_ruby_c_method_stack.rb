#!/usr/bin/env ruby

require 'json'
require 'webrick'
require 'fiddle'
require 'datadog'

# Simple HTTP server to capture crash reports
def start_crash_server(port)
  server = WEBrick::HTTPServer.new(
    Port: port,
    Logger: WEBrick::Log.new(File.open(File::NULL, "w")),
    AccessLog: []
  )

  crash_report = nil

  server.mount_proc '/' do |req, res|
    if req.request_method == 'POST'
      body = req.body
      crash_report = JSON.parse(body) rescue body
      puts "=== CRASH REPORT RECEIVED ==="
      puts JSON.pretty_generate(crash_report) if crash_report.is_a?(Hash)
      puts "=== END CRASH REPORT ==="
    end
    res.body = '{}'
  end

  Thread.new { server.start }
  [server, proc { crash_report }]
end

def test_with_multiple_c_methods
  puts "Testing with multiple C methods"
  "hello world".gsub(/world/) do |match|
    puts "In String#gsub block, matched: #{match}"
    {a: 1, b: 2}.each do |key, value|
      puts "In Hash#each block: #{key} => #{value}"
      if key == :a
        puts "About to crash from within nested C method calls"
        Fiddle.free(99)
      end
    end
  end
end

# Test function names extraction
def analyze_stack_for_method_types(runtime_stack)
  if runtime_stack && runtime_stack['frames']
    ruby_methods = []
    c_methods = []
    unknown_methods = []

    runtime_stack['frames'].each_with_index do |frame, i|
      function_name = frame['function'] || '<unknown>'
      file_name = frame['file'] || '<unknown>'

      # Heuristics to identify method types
      if file_name.include?('.rb') || file_name == '<unknown>'
        ruby_methods << "#{function_name} (#{file_name}:#{frame['line']})"
      elsif function_name.include?('#') || file_name.include?('array.c') || file_name.include?('hash.c') || file_name.include?('string.c')
        c_methods << "#{function_name} (#{file_name}:#{frame['line']})"
      else
        unknown_methods << "#{function_name} (#{file_name}:#{frame['line']})"
      end
    end

    puts "\n=== STACK ANALYSIS BY METHOD TYPE ==="
    puts "Ruby methods found:"
    ruby_methods.each { |m| puts "  - #{m}" }
    puts "C methods found:"
    c_methods.each { |m| puts "  - #{m}" }
    puts "Unknown/Other methods:"
    unknown_methods.each { |m| puts "  - #{m}" }

    return {
      ruby_count: ruby_methods.length,
      c_count: c_methods.length,
      unknown_count: unknown_methods.length
    }
  end

  return { ruby_count: 0, c_count: 0, unknown_count: 0 }
end

def run_crash_test(test_name, test_proc)
  puts "\n" + "="*60
  puts "RUNNING TEST: #{test_name}"
  puts "="*60

  # Start server
  server, get_crash_report = start_crash_server(9999)
  sleep 0.1 # Let server start

  puts "Forking process to test crashtracker..."


  pid = fork do
    begin
      puts "Child process started"

      # Configure crashtracker
      Datadog.configure do |c|
        c.agent.host = '127.0.0.1'
        c.agent.port = 9999
      end

      puts "Crashtracker configured, starting crash test..."

      # Run the specific test
      test_proc.call

    rescue => e
      puts "Unexpected error in child: #{e}"
      exit 1
    end
  end

  # Wait for child process
  Process.wait(pid)
  puts "Child process finished with status: #{$?.exitstatus}"

  # Give server time to receive the crash report
  sleep 1

  # Get and analyze the crash report
  crash_report = get_crash_report.call
  if crash_report
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    crash_file = "/tmp/#{test_name.downcase.gsub(/\s+/, '_')}_report_#{timestamp}.json"
    File.write(crash_file, JSON.pretty_generate(crash_report))
    puts "\nFull crash report written to: #{crash_file}"

    if crash_report.is_a?(Hash) && crash_report.dig('payload', 0, 'message')
      message = JSON.parse(crash_report.dig('payload', 0, 'message'))
      runtime_stack = message['experimental']['runtime_stack']

      if runtime_stack
        puts "\nRuntime stack format: #{runtime_stack['format']}"
        puts "Number of frames captured: #{runtime_stack['frames']&.length || 0}"
        puts "\nStack frames:"
        runtime_stack['frames']&.each_with_index do |frame, i|
          puts "  [#{i}] #{frame['function']} @ #{frame['file']}:#{frame['line']}"
        end

        # Save runtime stack to separate file
        runtime_stack_file = "/tmp/#{test_name.downcase.gsub(/\s+/, '_')}_runtime_stack_#{timestamp}.json"
        File.write(runtime_stack_file, JSON.pretty_generate(runtime_stack))
        puts "\nRuntime stack saved to: #{runtime_stack_file}"

        # Analyze method types
        method_counts = analyze_stack_for_method_types(runtime_stack)

        puts "\n=== TEST RESULTS ==="
        puts "Ruby methods captured: #{method_counts[:ruby_count]}"
        puts "C methods captured: #{method_counts[:c_count]}"
        puts "Unknown methods: #{method_counts[:unknown_count]}"

        if method_counts[:ruby_count] > 0 && method_counts[:c_count] > 0
          puts "✓ SUCCESS: Both Ruby and C methods captured in stack!"
        elsif method_counts[:ruby_count] > 0
          puts "⚠ PARTIAL: Only Ruby methods captured"
        elsif method_counts[:c_count] > 0
          puts "⚠ PARTIAL: Only C methods captured"
        else
          puts "✗ FAILURE: No recognizable methods captured"
        end

      else
        puts "No runtime_stack found in crash report"
      end
    else
      puts "Could not parse crash report structure"
    end
  else
    puts "No crash report received"
  end

  # Cleanup
  server.shutdown
  puts "Test #{test_name} complete.\n"
end

# Main execution
puts "Starting Ruby + C Method Stack Capture Test..."

run_crash_test("Multiple C Methods Stack", method(:test_with_multiple_c_methods))

puts "\n" + "="*60
puts "ALL TESTS COMPLETE"
puts "="*60
puts "This test validates that crashtracker can capture both:"
puts "1. Ruby method names and locations"
puts "2. C method names (like Array#each, Hash#each, String#gsub)"
puts "3. Mixed Ruby/C call stacks with proper frame information"
