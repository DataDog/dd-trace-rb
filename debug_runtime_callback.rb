require 'English'
require 'json'
require 'webrick'
require 'fiddle'
require 'datadog'

# Simple HTTP server to capture crash reports
def start_crash_server(port)
  server = WEBrick::HTTPServer.new(
    Port: port,
    Logger: WEBrick::Log.new(File.open(File::NULL, 'w')),
    AccessLog: []
  )

  crash_report = nil

  server.mount_proc '/' do |req, res|
    if req.request_method == 'POST'
      body = req.body
      crash_report = JSON.parse(body) rescue body
      puts '=== CRASH REPORT RECEIVED ==='
      puts JSON.pretty_generate(crash_report) if crash_report.is_a?(Hash)
      puts '=== END CRASH REPORT ==='
    end
    res.body = '{}'
  end

  Thread.new { server.start }
  [server, proc { crash_report }]
end

# Deep nested Ruby functions to create a complex runtime stack
class ComplexStackBuilder
  attr_accessor :counter, :data_store

  def initialize
    @counter = 0
    @data_store = {}
  end

  def increment_and_store(key, value)
    @counter += 1
    @data_store[key] = value
  end
end

def database_layer_query(query_id)
  builder = ComplexStackBuilder.new
  builder.increment_and_store("query_#{query_id}", "SELECT * FROM users WHERE id = #{query_id}")
  yield builder if block_given?
  builder
end

def orm_layer_find(model_id)
  puts "ORM Layer: Finding model #{model_id}"
  database_layer_query(model_id) do |builder|
    builder.increment_and_store('orm_operation', 'find')
    service_layer_process(builder)
  end
end

def service_layer_process(builder)
  puts 'Service Layer: Processing business logic'
  builder.increment_and_store('service_action', 'user_authentication')
  controller_layer_handle(builder)
end

def controller_layer_handle(builder)
  puts 'Controller Layer: Handling HTTP request'
  builder.increment_and_store('http_method', 'POST')
  middleware_stack_authenticate(builder)
end

def middleware_stack_authenticate(builder)
  puts 'Middleware: Authentication check'
  builder.increment_and_store('auth_status', 'validating')
  middleware_stack_authorize(builder)
end

def middleware_stack_authorize(builder)
  puts 'Middleware: Authorization check'
  builder.increment_and_store('auth_permissions', ['read', 'write'])
  middleware_stack_logging(builder)
end

def middleware_stack_logging(builder)
  puts 'Middleware: Request logging'
  builder.increment_and_store('request_id', "req_#{rand(10000)}")
  application_layer_router(builder)
end

def application_layer_router(builder)
  puts 'Application Router: Route resolution'
  builder.increment_and_store('route', '/api/v1/users')
  application_layer_dispatcher(builder)
end

def application_layer_dispatcher(builder)
  puts 'Application Dispatcher: Request dispatch'
  builder.increment_and_store('dispatch_time', Time.now.to_f)
  framework_layer_request_handler(builder)
end

def framework_layer_request_handler(builder)
  puts 'Framework: Request handler initialization'
  builder.increment_and_store('handler_type', 'RestfulHandler')
  framework_layer_response_builder(builder)
end

def framework_layer_response_builder(builder)
  puts 'Framework: Response builder setup'
  builder.increment_and_store('response_format', 'json')
  business_logic_user_service(builder)
end

def business_logic_user_service(builder)
  puts 'Business Logic: User service operations'
  builder.increment_and_store('user_operation', 'profile_update')
  business_logic_validation(builder)
end

def business_logic_validation(builder)
  puts 'Business Logic: Input validation'
  builder.increment_and_store('validation_rules', ['email_format', 'password_strength'])
  business_logic_transformation(builder)
end

def business_logic_transformation(builder)
  puts 'Business Logic: Data transformation'
  builder.increment_and_store('transform_operations', ['normalize', 'sanitize'])
  data_access_layer_connection(builder)
end

def data_access_layer_connection(builder)
  puts 'Data Access: Database connection setup'
  builder.increment_and_store('db_connection', 'postgresql://localhost:5432')
  data_access_layer_transaction(builder)
end

def data_access_layer_transaction(builder)
  puts 'Data Access: Transaction management'
  builder.increment_and_store('transaction_id', "tx_#{rand(100000)}")
  data_access_layer_query_execution(builder)
end

def data_access_layer_query_execution(builder)
  puts 'Data Access: Query execution'
  builder.increment_and_store('query_execution_plan', 'index_scan')
  caching_layer_check(builder)
end

def caching_layer_check(builder)
  puts 'Caching Layer: Cache lookup'
  builder.increment_and_store('cache_key', "user_profile_#{builder.counter}")
  caching_layer_miss(builder)
end

def caching_layer_miss(builder)
  puts 'Caching Layer: Cache miss, fetching from source'
  builder.increment_and_store('cache_miss', true)
  serialization_layer_encode(builder)
end

def serialization_layer_encode(builder)
  puts 'Serialization: Data encoding'
  builder.increment_and_store('encoding_format', 'utf-8')
  serialization_layer_compress(builder)
end

def serialization_layer_compress(builder)
  puts 'Serialization: Data compression'
  builder.increment_and_store('compression', 'gzip')
  network_layer_prepare(builder)
end

def network_layer_prepare(builder)
  puts 'Network Layer: Connection preparation'
  builder.increment_and_store('network_protocol', 'tcp')
  network_layer_send(builder)
end

def network_layer_send(builder)
  puts 'Network Layer: Data transmission'
  builder.increment_and_store('transmission_size', builder.data_store.to_s.length)
  security_layer_encrypt(builder)
end

def security_layer_encrypt(builder)
  puts 'Security Layer: Data encryption'
  builder.increment_and_store('encryption_algorithm', 'AES-256')
  security_layer_sign(builder)
end

def security_layer_sign(builder)
  puts 'Security Layer: Digital signature'
  builder.increment_and_store('signature_algorithm', 'RSA-SHA256')
  monitoring_layer_metrics(builder)
end

def monitoring_layer_metrics(builder)
  puts 'Monitoring: Collecting metrics'
  builder.increment_and_store('metrics_collected', ['response_time', 'memory_usage'])
  monitoring_layer_alerts(builder)
end

def monitoring_layer_alerts(builder)
  puts 'Monitoring: Alert system check'
  builder.increment_and_store('alert_rules', ['high_cpu', 'memory_threshold'])
  final_crash_point(builder)
end

def final_crash_point(builder)
  puts 'Final Layer: About to crash with complex stack'
  puts "Stack depth achieved: #{builder.counter} operations"
  puts "Data store size: #{builder.data_store.size} entries"

  # Multiple complex operations before crash
  complex_array = Array.new(1000) { |i| "item_#{i}" }
  complex_hash = Hash[complex_array.map { |item| [item, rand(1000)] }]

  # Some string operations
  complex_string = complex_hash.keys.join(',') * 10

  # Nested data structure
  nested_data = {
    level1: {
      level2: {
        level3: {
          data: complex_hash,
          metadata: builder.data_store,
          processing_info: {
            start_time: Time.now.to_f,
            operations: builder.counter,
            final_string_length: complex_string.length
          }
        }
      }
    }
  }

  puts "Final nested data structure created with #{nested_data.to_s.length} characters"

  4.times do |i|
    Fiddle.free(42)
  end
end

def main_crash_test
  puts 'Starting crash test with deeply nested functions and complex operations'
  puts 'This will create a runtime stack with 25+ levels of function calls'
  orm_layer_find(12345)
end

# Main test
puts 'Starting standalone crashtracker test...'

# Start server
server, get_crash_report = start_crash_server(9999)
sleep 0.1 # Let server start

puts 'Forking process to test crashtracker...'

pid = fork do
  begin
    puts 'Child process started'

    # Configure crashtracker
    Datadog.configure do |c|
      c.agent.host = '127.0.0.1'
      c.agent.port = 9999
    end

    puts 'Crashtracker configured, starting crash test...'

    # Call our nested function that will crash
    main_crash_test

  rescue => e
    puts "Unexpected error in child: #{e}"
    exit 1
  end
end

# Wait for child process
Process.wait(pid)
puts "Child process finished with status: #{$CHILD_STATUS.exitstatus}"

# Give server time to receive the crash report
sleep 1

# Get and save the crash report
crash_report = get_crash_report.call
if crash_report
  # Write full crash report to tmp file
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  crash_file = "/tmp/crashtracker_report_#{timestamp}.json"
  File.write(crash_file, JSON.pretty_generate(crash_report))
  puts '\n=== CRASH REPORT SAVED ==='
  puts "Full crash report written to: #{crash_file}"

  puts '\n=== RUNTIME STACK ANALYSIS ==='
  if crash_report.is_a?(Hash) && crash_report.dig('payload', 0, 'message')
    message = JSON.parse(crash_report.dig('payload', 0, 'message'))
    runtime_stack = message['experimental']['runtime_stack']
    if runtime_stack
      puts "Runtime stack format: #{runtime_stack['format']}"
      puts "Number of frames captured: #{runtime_stack['frames']&.length || 0}"
      puts '\nStack frames:'
      runtime_stack['frames']&.each_with_index do |frame, i|
        puts "  [#{i}] #{frame['function']} @ #{frame['file']}:#{frame['line']}"
      end

      runtime_stack_file = "/tmp/runtime_stack_#{timestamp}.json"
      File.write(runtime_stack_file, JSON.pretty_generate(runtime_stack))
      puts "\nRuntime stack saved to: #{runtime_stack_file}"
    else
      puts 'No runtime_stack found in crash report'
    end
  else
    puts 'Could not parse crash report structure'
  end
else
  puts 'No crash report received'
end

# Cleanup
server.shutdown
puts '\nTest complete.'
