# typed: true

module Datadog
  module Profiling
    # Used to report profiling data to Datadog.
    # Methods prefixed with _native_ are implemented in `http_transport.c`
    class HttpTransport
      def initialize(agent_settings:, site:, api_key:, tags:, upload_timeout_seconds:)
        @upload_timeout_milliseconds = (upload_timeout_seconds * 1_000).to_i

        validate_agent_settings(agent_settings)

        if site && api_key && agentless_allowed?
          create_agentless_exporter(site, api_key, tags)
        else
          create_agent_exporter(base_url_from(agent_settings), tags)
        end
      end

      def export(flush)
        do_export(
          # why "timespec"?
          # libddprof represents time using POSIX's struct timespec, see
          # https://www.gnu.org/software/libc/manual/html_node/Time-Types.html
          # aka they separate the seconds part from the nanoseconds part
          start_timespec_seconds: flush.start.tv_sec,
          start_timespec_nanoseconds: flush.start.tv_nsec,
          finish_timespec_seconds: flush.finish.tv_sec,
          finish_timespec_nanoseconds: flush.finish.tv_nsec,

          pprof_file_name: flush.pprof_file_name,
          pprof_data: flush.pprof_data,
          code_provenance_file_name: flush.code_provenance_file_name,
          code_provenance_data: flush.code_provenance_data,
        )
      end

      private

      def base_url_from(agent_settings)
        "#{agent_settings.ssl ? 'https' : 'http'}://#{agent_settings.hostname}:#{agent_settings.port}/"
      end

      # FIXME: Re-evaluate our plans for these before merging this anywhere. We should at least provide clearer error
      # messages and next steps for customers, the current messages are too cryptic. Ideally, we would still support
      # Unix Domain Socket for reporting data.
      def validate_agent_settings(agent_settings)
        if agent_settings.adapter == Transport::Ext::UnixSocket::ADAPTER
          raise ArgumentError, 'Unsupported agent configuration for profiling: Unix Domain Sockets are currently unsupported.'
        end

        if agent_settings.deprecated_for_removal_transport_configuration_proc
          raise ArgumentError, 'Unsupported agent configuration for profiling: custom c.tracer.transport_options is currently unsupported.'
        end
      end

      def create_agentless_exporter(site, api_key, tags)
        _native_create_agentless_exporter(site, api_key, tags)
      end

      def create_agent_exporter(base_url, tags)
        _native_create_agent_exporter(base_url, tags)
      end

      def do_export(
        start_timespec_seconds:,
        start_timespec_nanoseconds:,
        finish_timespec_seconds:,
        finish_timespec_nanoseconds:,
        pprof_file_name:,
        pprof_data:,
        code_provenance_file_name:,
        code_provenance_data:
      )
        _native_do_export(
          start_timespec_seconds,
          start_timespec_nanoseconds,
          finish_timespec_seconds,
          finish_timespec_nanoseconds,
          pprof_file_name,
          pprof_data,
          code_provenance_file_name,
          code_provenance_data,
        )
      end
    end
  end
end

# New structure for Flush:
# start, finish, pprof_file_name, pprof_data, code_provenance_file_name, code_provenance_data
