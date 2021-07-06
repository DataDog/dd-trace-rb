require 'pry'
require 'ddtrace'

class LibddprofAdapter
  include Datadog::Profiling::Transport::Client

  ResponseAdapter = Struct.new(:code, :body)

  def call(env)
    send(env.verb, env)
  end

  def post(env)
    post = ::Datadog::Vendor::Net::HTTP::Post::Multipart.new(
      env.path,
      env.form,
      env.headers
    )

    url = "https://intake.profile.datadoghq.com#{env.path}"
    headers = post.each_header.to_a
    body = post.body_stream.read
    timeout_ms = 1_000

    success = libddprof_send(url, headers, body, timeout_ms)
    Datadog.logger.info "Libddprof reporting success? #{success}"

    if success
      Datadog::Transport::HTTP::Adapters::Net::Response.new(ResponseAdapter.new(200, ""))
    else
      Datadog::Transport::HTTP::Adapters::Net::Response.new(ResponseAdapter.new(400, ""))
    end
  end

  private

  def libddprof_send(url, headers, body, timeout_ms)
    native_send(url, headers, body, timeout_ms)
  end
end

require 'ddtrace_native_extension'

Datadog::Profiling::Transport::HTTP::Builder::REGISTRY.set(LibddprofAdapter, :libddprof)

class Datadog::Profiling::Scheduler
  DEFAULT_INTERVAL_SECONDS = 10
end

Datadog.configure do |c|
  c.service = 'ivoanjo-testing-libddprof'
  c.env = 'staging'
  c.profiling.enabled = true
  c.diagnostics.debug = true
  c.tracer.port = 8111
  c.tracer.transport_options = proc { |t| t.adapter :libddprof }
end

sleep
