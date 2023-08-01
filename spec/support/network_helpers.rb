module NetworkHelpers
  TEST_AGENT_HOST = ENV['DD_TEST_AGENT_HOST'] || 'testagent'
  TEST_AGENT_PORT = ENV['DD_TEST_AGENT_PORT'] || 9126

  # Returns a TCP "host:port" endpoint currently available
  # for listening in the local machine
  #
  # @return [String] "host:port" available for listening
  def available_endpoint
    "0.0.0.0:#{available_port}"
  end

  # Finds a TCP port currently available
  # for listening in the local machine
  #
  # @return [Integer] port available for listening
  def available_port
    server = TCPServer.new('0.0.0.0', 0)
    server.addr[1].tap do
      server.close
    end
  end

  def test_agent_running?
    @test_agent_running ||= check_availability_by_http_request(TEST_AGENT_HOST, TEST_AGENT_PORT)
  end

  # Yields an exclusion allowing WebMock traffic to APM Test Agent given an inputted block that calls webmock
  # function, ie: call_web_mock_function_with_agent_host_exclusions { [options] webmock.disable! options }
  #
  # @yield [Hash] webmock exclusions to call webmock block with
  def call_web_mock_function_with_agent_host_exclusions
    if ENV['DD_AGENT_HOST'] == 'testagent' && test_agent_running?
      yield allow: "http://#{TEST_AGENT_HOST}:#{TEST_AGENT_PORT}"
    else
      yield({})
    end
  end

  # Checks for availability of a Datadog agent or APM Test Agent by trying /info endpoint
  #
  # @return [Boolean] if agent on inputted host / port combo is running
  def check_availability_by_http_request(host, port)
    uri = URI("http://#{host}:#{port}/info")
    request = Net::HTTP::Get.new(uri)
    request[Datadog::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = '1'
    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end
    response.is_a?(Net::HTTPSuccess)
  rescue SocketError
    false
  end

  # Adds the DD specific tracer configuration environment to the inputted tracer headers as
  # a comma separated string of `k=v` pairs.
  #
  # @return [Hash] trace headers
  def parse_tracer_config_and_add_to_headers(trace_headers)
    dd_env_variables = resolve_service_names(trace_headers)

    schema_version = Datadog.configuration.tracing.contrib.global_default_service_name.enabled ? "v1" : "v0"

    trace_variables = dd_env_variables.map { |key, value| "#{key}=#{value}" }.join(',')
    if trace_variables.empty?
      trace_variables = "DD_TRACE_SPAN_ATTRIBUTE_SCHEMA=#{schema_version}"
    else
      trace_variables += ",DD_TRACE_SPAN_ATTRIBUTE_SCHEMA=#{schema_version}"
    end
    trace_headers['X-Datadog-Trace-Env-Variables'] = trace_variables
    trace_headers
  end
end

def resolve_service_names(trace_headers)
  dd_service = Datadog.configuration.service
  instrumented_integrations = Datadog.configuration.tracing.instrumented_integrations
  # Get all DD_ variables from ENV
  dd_env_variables = ENV.to_h.select { |key, _| key.start_with?('DD_') }

  instrumented_integrations.flat_map do |name, integration|
    config = integration.configuration.to_h
    if config.key? :service_name
      service_name = config[:service_name]
      integration_name_to_component = { :mongo => 'mongodb', :http => 'net/http' }
      component = integration_name_to_component.fetch(name, name.to_s)
      dd_env_variables["DD_#{component.upcase}_SERVICE"] = service_name
    end
  end

  s = get_span
  if s && s.meta['component']
    component = s.meta['component']
    if ENV['DD_CONFIGURED_INTEGRATION_INSTANCE_SERVICE']
      dd_integration_service = ENV['DD_CONFIGURED_INTEGRATION_INSTANCE_SERVICE']
      dd_env_variables["DD_#{component.upcase}_SERVICE"] = dd_integration_service
    elsif ENV['DD_CONFIGURED_INTEGRATION_SERVICE']
      dd_integration_service = ENV['DD_CONFIGURED_INTEGRATION_SERVICE']
      dd_env_variables["DD_#{component.upcase}_SERVICE"] = dd_integration_service
    end

    component_to_integration_name = { 'mongodb' => 'mongo', 'net/http' => 'http' }
    if dd_service != s.service && s.service != dd_env_variables["DD_#{component.upcase}_SERVICE"]
      dd_env_variables["DD_#{component.upcase}_SERVICE"] = Datadog.configuration.tracing[component_to_integration_name.fetch(component, component).to_sym][:service_name]
    end
    # if dd_service != s.service && s.service != dd_env_variables["DD_#{component.upcase}_SERVICE"]
    #   byebug
    #   puts s.service
    # end
    dd_env_variables['DD_SERVICE'] = dd_service
  end
  dd_env_variables
end

def get_span
  s = nil
  fetch_spans.each do |sp|
    if sp.meta["component"]
      s = sp
      break
    end
  end
  s
end
