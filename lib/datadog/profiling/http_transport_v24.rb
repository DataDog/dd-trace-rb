# typed: true

require 'net/http'
require 'time'
require 'json'
require_relative '../core/vendor/multipart-post/net/http/post/multipart'

module Datadog
  module Profiling
    # Hacky replacement for HttpTransport using net-http and reporting in intake v2.4 format
    class HttpTransportV24
      def initialize(agent_settings:, site:, api_key:, upload_timeout_seconds:)
        @upload_timeout_seconds = upload_timeout_seconds

        if agentless?(site, api_key)
          @api_key = api_key
          @url = URI.parse("https://intake.profile.#{site}/api/v2/profile")
        else
          @url = URI.parse("#{base_url_from(agent_settings)}/profiling/v1/input")
        end
      end

      def export(flush) # rubocop:disable Metrics/MethodLength
        event = {
          attachments: [flush.pprof_file_name],
          tags_profiler: flush.tags_as_array.map { |pair| pair.join(':') }.join(','),
          start: flush.start.iso8601,
          end: flush.finish.iso8601,
          family: 'ruby',
          version: '4',
          extra: {
            ruby_description: RUBY_DESCRIPTION,
            os: `uname -a`,
            _profiler_list: 'walltime', # FIXME: Should not be hardcoded
            _private_test: 'this is a private arg test', # FIXME
          },
        }

        request = Datadog::Core::Vendor::Net::HTTP::Post::Multipart.new(
          @url.path,
          {
            'event' => Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
              StringIO.new(JSON.dump(event)),
              'application/json',
              'event.json',
            ),
            flush.pprof_file_name => Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
              StringIO.new(flush.pprof_data),
              'text/plain',
              flush.pprof_file_name,
            ),
            flush.code_provenance_file_name => Datadog::Core::Vendor::Multipart::Post::UploadIO.new(
              StringIO.new(flush.code_provenance_data),
              'text/plain',
              flush.code_provenance_file_name,
            ),
          }
        )

        request['DD-API-KEY'] = @api_key if @api_key
        request['DD-EVP-ORIGIN'] = 'dd-trace-rb'
        request['DD-EVP-ORIGIN-VERSION'] = "HttpTransportV24-#{DDTrace::VERSION::STRING}"

        result = Net::HTTP.start(@url.host, @url.port) do |http|
          http.open_timeout = @upload_timeout_seconds
          http.read_timeout = @upload_timeout_seconds
          http.request(request)
        end

        if (200..299).cover?(result.code.to_i)
          Datadog.logger.debug('Successfully reported profiling data')
          true
        else
          Datadog.logger.error("Failed to report profiling data: server returned #{result.inspect}")
          false
        end
      end

      def agentless?(site, api_key)
        site && api_key && Core::Environment::VariableHelpers.env_to_bool(Profiling::Ext::ENV_AGENTLESS, false)
      end

      def base_url_from(agent_settings)
        case agent_settings.adapter
        when Datadog::Transport::Ext::HTTP::ADAPTER
          "#{agent_settings.ssl ? 'https' : 'http'}://#{agent_settings.hostname}:#{agent_settings.port}"
        when Datadog::Transport::Ext::UnixSocket::ADAPTER
          "unix://#{agent_settings.uds_path}"
        else
          raise ArgumentError, "Unexpected adapter: #{agent_settings.adapter}"
        end
      end
    end
  end
end
