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

# Nested Ruby functions to create a meaningful stack
def level_5
  puts "In level_5 - about to crash"
  # Trigger segfault
  Fiddle.free(42)
end

def level_4
  puts "In level_4"
  level_5
end

def level_3
  puts "In level_3"
  level_4
end

def level_2
  puts "In level_2"
  level_3
end

def level_1
  puts "In level_1"
  level_2
end

def main_crash_test
  puts "Starting crash test with nested functions"
  level_1
end

# Main test
puts "Starting standalone crashtracker test..."

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

    # Call our nested function that will crash
    main_crash_test

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

# Get and save the crash report
crash_report = get_crash_report.call
if crash_report
  # Write full crash report to tmp file
  timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
  crash_file = "/tmp/crashtracker_report_#{timestamp}.json"
  File.write(crash_file, JSON.pretty_generate(crash_report))
  puts "\n=== CRASH REPORT SAVED ==="
  puts "Full crash report written to: #{crash_file}"

  puts "\n=== RUNTIME STACK ANALYSIS ==="
  if crash_report.is_a?(Hash) && crash_report.dig('payload', 0, 'message')
    message = JSON.parse(crash_report.dig('payload', 0, 'message'))
    runtime_stack = message['experimental']['runtime_stack']
    if runtime_stack
      puts "Runtime stack format: #{runtime_stack['format']}"
      puts "Number of frames captured: #{runtime_stack['frames']&.length || 0}"
      puts "\nStack frames:"
      runtime_stack['frames']&.each_with_index do |frame, i|
        puts "  [#{i}] #{frame['function']} @ #{frame['file']}:#{frame['line']}"
      end

      runtime_stack_file = "/tmp/runtime_stack_#{timestamp}.json"
      File.write(runtime_stack_file, JSON.pretty_generate(runtime_stack))
      puts "\nRuntime stack saved to: #{runtime_stack_file}"
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
puts "\nTest complete."
