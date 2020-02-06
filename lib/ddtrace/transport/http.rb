require 'ddtrace/version'
require 'ddtrace/ext/runtime'
require 'ddtrace/ext/transport'

require 'ddtrace/runtime/container'

require 'ddtrace/transport/http/builder'
require 'ddtrace/transport/http/api'

require 'ddtrace/transport/http/adapters/net'
require 'ddtrace/transport/http/adapters/test'
require 'ddtrace/transport/http/adapters/unix_socket'

module Datadog
  module Transport
    # Namespace for HTTP transport components
    module HTTP
      module_function

      # Builds a new Transport::HTTP::Client
      def new(&block)
        Builder.new(&block).to_client
      end

      # Builds a new Transport::HTTP::Client with default settings
      # Pass a block to override any settings.
      def default(options = {})
        new do |transport|
          transport.adapter :net_http, default_hostname, default_port
          transport.headers default_headers

          apis = API.defaults

          transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
          transport.api API::V3, apis[API::V3], fallback: API::V2
          transport.api API::V2, apis[API::V2]

          # Apply any settings given by options
          unless options.empty?
            # Change hostname/port
            if options.key?(:hostname) || options.key?(:port)
              hostname = options.fetch(:hostname, default_hostname)
              port = options.fetch(:port, default_port)
              transport.adapter :net_http, hostname, port
            end

            # Change default API
            transport.default_api = options[:api_version] if options.key?(:api_version)

            # Add headers
            transport.headers options[:headers] if options.key?(:headers)

            # Execute on_build callback
            options[:on_build].call(transport) if options[:on_build].is_a?(Proc)
          end

          # Call block to apply any customization, if provided.
          yield(transport) if block_given?
        end
      end

      def default_headers
        {
          Datadog::Ext::Transport::HTTP::HEADER_META_LANG => Datadog::Ext::Runtime::LANG,
          Datadog::Ext::Transport::HTTP::HEADER_META_LANG_VERSION => Datadog::Ext::Runtime::LANG_VERSION,
          Datadog::Ext::Transport::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Ext::Runtime::LANG_INTERPRETER,
          Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::Ext::Runtime::TRACER_VERSION
        }.tap do |headers|
          # Add container ID, if present.
          container_id = Datadog::Runtime::Container.container_id
          unless container_id.nil?
            headers[Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID] = container_id
          end
        end
      end

      KUBERNETES_SERVICE_HOST = ENV['KUBERNETES_SERVICE_HOST']
      KUBERNETES_PORT_443_TCP_PORT = ENV['KUBERNETES_PORT_443_TCP_PORT']

      def default_hostname
        hostname_env = ENV[Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST]
        return hostname_env if hostname_env && !hostname_env.empty?

        begin
          # DEV: WIP WIP WIP
          STDERR.puts 'K8S hostname detection started'
          kube_token = File.read('/var/run/secrets/kubernetes.io/serviceaccount/token')

          timeout = 1
          res = Net::HTTP.start(KUBERNETES_SERVICE_HOST,
                                KUBERNETES_PORT_443_TCP_PORT,
                                use_ssl: true,
                                verify_mode: OpenSSL::SSL::VERIFY_NONE,
                                open_timeout: timeout,
                                read_timeout: timeout) do |http|
            request = Net::HTTP::Get.new '/api/v1/namespaces/default/pods/'
            request['Authorization'] = "Bearer #{kube_token}"

            http.request(request)
          end

          STDERR.puts 'K8S hostname detection finished:'
          STDERR.puts res.body

          if res.code.to_i.between?(200, 299)
            body = JSON.parse(res.body)
            this = body['items'].find { |x| x['metadata']['name'] == ENV['HOSTNAME'] }
            node = this['spec']['nodeName']
            node_pods = body['items'].select { |x| x['spec']['nodeName'] == node }
            agent_pod = node_pods.find do |x|
              x['spec']['containers'].find do |y|
                y['ports'] && y['ports'].find do |z|
                  z['name'] == 'traceport'
                end
              end
            end
            agent_pod_ip = agent_pod['status']['podIP']
            STDERR.puts "AGENT_POD_ID: #{agent_pod_ip}"

            return agent_pod_ip
          end
        rescue => e
          STDERR.puts 'K8S hostname detection failed with error:'
          STDERR.puts e.message
          STDERR.puts e.backtrace
        end

        Datadog::Ext::Transport::HTTP::DEFAULT_HOST
      end

      def default_port
        ENV.fetch(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT, Datadog::Ext::Transport::HTTP::DEFAULT_PORT).to_i
      end

      # Add adapters to registry
      Builder::REGISTRY.set(Adapters::Net, :net_http)
      Builder::REGISTRY.set(Adapters::Test, :test)
      Builder::REGISTRY.set(Adapters::UnixSocket, :unix)
    end
  end
end
