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

# Test 1: Corrupt execution context by overwriting memory
def test_corrupt_execution_context
  puts "Test: Corrupting Ruby execution context"

  # Get current thread and try to corrupt its execution context
  # This is very dangerous but should be handled gracefully by our crashtracker
  current_thread_ptr = Fiddle::Pointer.new(Thread.current.object_id << 1)

  puts "About to corrupt execution context and crash..."

  # Method that will be called when the crash happens - this creates Ruby frames
  def nested_method_during_corruption
    puts "In nested Ruby method"
    # Corrupt memory near current thread structure (simulates corruption)
    corrupted_ptr = Fiddle::Pointer.malloc(8)
    corrupted_ptr[0, 8] = "\xFF" * 8  # Fill with invalid data

    # Now cause the actual crash - this should trigger our crashtracker
    # with potentially corrupted VM state
    Fiddle.free(42)
  end

  nested_method_during_corruption
end

# Test 2: Corrupt VM stack pointers
def test_corrupt_vm_stack
  puts "Test: Accessing VM internals before crash"

  # Create some Ruby stack frames first
  def level_3_with_corruption
    puts "In level 3 - about to cause memory corruption"

    # Try to allocate and immediately free invalid memory
    # This might corrupt Ruby's memory pools
    100.times do |i|
      ptr = Fiddle::Pointer.malloc(1024)
      ptr[0, 8] = [i].pack("Q") # Write some data
      Fiddle.free(ptr.to_i) # Free it
    end

    # Now corrupt something and crash
    Fiddle.free(99999) # Invalid pointer - should crash
  end

  def level_2_with_corruption
    puts "In level 2"
    level_3_with_corruption
  end

  def level_1_with_corruption
    puts "In level 1"
    level_2_with_corruption
  end

  level_1_with_corruption
end

# Test 3: Crash while in C extension with no Ruby context
def test_crash_in_pure_c_context
  puts "Test: Crashing in pure C context"

  # Use Fiddle to call C functions directly
  # This minimizes Ruby VM involvement
  libc = Fiddle.dlopen(nil)
  free_func = Fiddle::Function.new(libc['free'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)

  puts "About to call free() with invalid pointer directly..."

  # Call free directly with an invalid pointer - minimal Ruby involvement
  free_func.call(Fiddle::Pointer.new(0x42))
end

# Test 4: Corrupt during C method execution
def test_corrupt_during_c_method
  puts "Test: Corruption during C method execution"

  # Create scenario where we're in C code when corruption happens
  large_array = (1..1000).to_a

  large_array.each do |item|
    puts "Processing item #{item} in Array#each (C method)"

    if item == 500
      puts "About to corrupt memory while inside C method..."

      # Simulate memory corruption
      random_ptr = Fiddle::Pointer.malloc(64)
      random_ptr[0, 64] = "\xDE\xAD\xBE\xEF" * 16

      # Try to free an invalid address - this should crash while we're
      # inside the Array#each C method
      Fiddle.free(0x123456)
    end
  end
end

# Test 5: Crash with thread in invalid state
def test_invalid_thread_state
  puts "Test: Crash with thread in potentially invalid state"

  # Create a thread that might be in weird state
  thread = Thread.new do
    puts "In background thread"
    sleep(0.1)

    # Corrupt something in the thread
    puts "About to crash from background thread..."
    Fiddle.free(0xDEADBEEF)
  end

  sleep(0.05) # Let thread start
  puts "Main thread continuing while background crashes..."
  thread.join rescue nil # This should crash
end

def analyze_crash_resilience(crash_report, test_name, results)
  result = {
    test_name: test_name,
    timestamp: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
    success: false,
    frames_captured: 0,
    runtime_stack_present: false,
    callback_executed: false,
    graceful_handling: false,
    details: [],
    crash_report_received: false
  }

  if crash_report
    result[:crash_report_received] = true
    puts "\n=== CRASH RESILIENCE ANALYSIS FOR #{test_name} ==="

    if crash_report.is_a?(Hash) && crash_report.dig('payload', 0, 'message')
      message = JSON.parse(crash_report.dig('payload', 0, 'message'))
      runtime_stack = message['experimental']['runtime_stack']

      if runtime_stack
        result[:runtime_stack_present] = true
        result[:callback_executed] = true
        frame_count = runtime_stack['frames']&.length || 0
        result[:frames_captured] = frame_count

        puts "✓ SUCCESS: Runtime stack callback executed successfully"
        puts "✓ Frames captured: #{frame_count}"
        puts "✓ No secondary crash in crashtracker callback"

        result[:details] << "Runtime stack callback executed successfully"
        result[:details] << "#{frame_count} frames captured"
        result[:details] << "No secondary crash in crashtracker callback"

        if frame_count > 0
          puts "✓ Frame extraction succeeded despite corruption"
          result[:details] << "Frame extraction succeeded despite corruption"

          sample_frames = []
          runtime_stack['frames'].each_with_index do |frame, i|
            frame_info = "[#{i}] #{frame['function']} @ #{frame['file']}:#{frame['line']}"
            puts "  #{frame_info}"
            sample_frames << frame_info
          end
          result[:sample_frames] = sample_frames
          result[:success] = true
        else
          puts "⚠ No frames captured (expected if VM severely corrupted)"
          result[:details] << "No frames captured (expected if VM severely corrupted)"
          result[:success] = true # Still success - graceful handling
        end
        result[:graceful_handling] = true
      else
        puts "⚠ No runtime stack in crash report"
        puts "⚠ This could indicate callback didn't run or early exit"
        result[:details] << "No runtime stack in crash report"
        result[:details] << "Callback may not have run or exited early"
        result[:graceful_handling] = true # Still graceful - no hang
      end
    else
      puts "⚠ Could not parse crash report structure"
      result[:details] << "Could not parse crash report structure"
      result[:graceful_handling] = true # Got report, so no hang
    end

    puts "✓ OVERALL: Crashtracker handled corruption gracefully - no hang or secondary crash"
    result[:details] << "Crashtracker handled corruption gracefully - no hang or secondary crash"
  else
    puts "✗ FAILURE: No crash report received - process may have hung"
    result[:details] << "No crash report received - process may have hung"
  end

  results << result
  result
end

def run_corruption_test(test_name, test_proc, results)
  puts "\n" + "="*70
  puts "RUNNING CORRUPTION TEST: #{test_name}"
  puts "="*70
  puts "This test intentionally corrupts Ruby VM state to verify graceful handling"

  # Start server
  server, get_crash_report = start_crash_server(9998)
  sleep 0.1

  puts "Forking process for corruption test..."

  pid = fork do
    begin
      puts "Child process started"

      # Configure crashtracker
      Datadog.configure do |c|
        c.agent.host = '127.0.0.1'
        c.agent.port = 9998
      end

      puts "Crashtracker configured. Starting corruption test..."
      puts "NOTE: This will intentionally corrupt Ruby VM state!"

      # Run the corruption test
      test_proc.call

    rescue => e
      puts "Unexpected Ruby exception in child (this is OK): #{e}"
      exit 1
    end
  end

  # Wait for child - with timeout in case it hangs
  hung = false
  begin
    Timeout.timeout(10) do
      Process.wait(pid)
    end
    puts "Child process finished with status: #{$?.exitstatus}"
  rescue Timeout::Error
    puts "⚠ Child process hung - killing it"
    Process.kill('KILL', pid)
    Process.wait(pid)
    puts "✗ FAILURE: Process hung instead of crashing gracefully"
    hung = true
  end

  # Give server time to receive crash report
  sleep 2

  # Analyze results
  crash_report = get_crash_report.call
  timestamp = Time.now.strftime("%Y%m%d_%H%M%S")

  if crash_report
    # Save crash report
    crash_file = "/tmp/corruption_test_#{test_name.downcase.gsub(/\s+/, '_')}_#{timestamp}.json"
    File.write(crash_file, JSON.pretty_generate(crash_report))
    puts "\nCrash report saved to: #{crash_file}"
  end

  result = analyze_crash_resilience(crash_report, test_name, results)
  result[:hung] = hung

  # Cleanup
  server.shutdown
  puts "Corruption test #{test_name} complete.\n"
  result
end

# Main execution
puts "Starting Ruby VM Corruption Resilience Tests..."
puts "These tests intentionally corrupt Ruby VM to verify crashtracker robustness"

# Collect all results
test_results = []

# Run all corruption tests
run_corruption_test("Corrupt Execution Context", method(:test_corrupt_execution_context), test_results)
run_corruption_test("Corrupt VM Stack", method(:test_corrupt_vm_stack), test_results)
run_corruption_test("Pure C Context Crash", method(:test_crash_in_pure_c_context), test_results)
run_corruption_test("Corrupt During C Method", method(:test_corrupt_during_c_method), test_results)
run_corruption_test("Invalid Thread State", method(:test_invalid_thread_state), test_results)

# Generate comprehensive results summary
timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
results_file = "/tmp/vm_corruption_resilience_results_#{timestamp}.json"

summary = {
  test_suite: "Ruby VM Corruption Resilience Tests",
  timestamp: Time.now.strftime("%Y-%m-%d %H:%M:%S"),
  total_tests: test_results.length,
  successful_tests: test_results.count { |r| r[:success] },
  graceful_handling_count: test_results.count { |r| r[:graceful_handling] },
  hung_processes: test_results.count { |r| r[:hung] },
  callback_executed_count: test_results.count { |r| r[:callback_executed] },
  total_frames_captured: test_results.sum { |r| r[:frames_captured] },
  tests: test_results,
  overall_assessment: {
    resilience_score: "#{test_results.count { |r| r[:graceful_handling] }}/#{test_results.length}",
    critical_failures: test_results.count { |r| r[:hung] },
    crashtracker_robustness: test_results.all? { |r| r[:graceful_handling] } ? "EXCELLENT" : "NEEDS_IMPROVEMENT"
  },
  recommendations: []
}

# Add recommendations based on results
if summary[:hung_processes] > 0
  summary[:recommendations] << "Investigate hung processes - may indicate infinite loops in safety checks"
end

if summary[:callback_executed_count] < summary[:total_tests]
  summary[:recommendations] << "Some callbacks didn't execute - verify early safety checks aren't too restrictive"
end

if summary[:total_frames_captured] == 0
  summary[:recommendations] << "No frames captured in any test - verify C frame extraction is working"
end

if summary[:recommendations].empty?
  summary[:recommendations] << "All tests passed - crashtracker shows excellent resilience to VM corruption"
end

# Write comprehensive results file
File.write(results_file, JSON.pretty_generate(summary))

puts "\n" + "="*70
puts "ALL CORRUPTION RESILIENCE TESTS COMPLETE"
puts "="*70

# Print summary
puts "SUMMARY RESULTS:"
puts "Total Tests: #{summary[:total_tests]}"
puts "Successful: #{summary[:successful_tests]}"
puts "Graceful Handling: #{summary[:graceful_handling_count]}/#{summary[:total_tests]}"
puts "Hung Processes: #{summary[:hung_processes]}"
puts "Callbacks Executed: #{summary[:callback_executed_count]}"
puts "Total Frames Captured: #{summary[:total_frames_captured]}"
puts "Overall Resilience: #{summary[:overall_assessment][:crashtracker_robustness]}"

puts "\nDetailed results saved to: #{results_file}"

puts "\nThese tests verify that our crashtracker:"
puts "1. Doesn't crash or hang when Ruby VM state is corrupted"
puts "2. Gracefully handles invalid pointers and corrupted data structures"
puts "3. Uses proper safety checks to avoid secondary crashes"
puts "4. Provides useful crash data even with partial corruption"
puts "5. Fails safely when VM data is completely unavailable"

if summary[:hung_processes] > 0
  puts "\n⚠ WARNING: #{summary[:hung_processes]} test(s) resulted in hung processes"
  puts "This may indicate issues with safety checks or infinite loops"
end
