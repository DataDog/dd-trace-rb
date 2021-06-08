require 'ddtrace/ext/profiling'
require 'ddtrace/utils/compression'
require 'ddtrace/vendor/multipart-post/multipart/post/composite_read_io'

require 'ddtrace/transport/http/api/endpoint'
require 'ddtrace/profiling/transport/http/response'

module Datadog
  module Profiling
    module Transport
      module HTTP
        module API
          # Datadog API endpoint for profiling
          class Endpoint < Datadog::Transport::HTTP::API::Endpoint
            include Datadog::Ext::Profiling::Transport::HTTP

            # These tags are read from the flush object (see below) directly and so we ignore any extra copies that
            # may come in the tags hash to avoid duplicates.
            TAGS_TO_IGNORE_IN_TAGS_HASH = %w[service env version].freeze
            private_constant :TAGS_TO_IGNORE_IN_TAGS_HASH

            attr_reader \
              :encoder

            def initialize(path, encoder)
              super(:post, path)
              @encoder = encoder
            end

            def call(env, &block)
              # Build request
              env.form = build_form(env)

              # Send request
              http_response = super(env, &block)

              # Build response
              Profiling::Transport::HTTP::Response.new(http_response)
            end

            def build_form(env)
              flush = env.request.parcel.data
              pprof_file, types = build_pprof(flush)

              form = {
                # NOTE: Redundant w/ 'runtime-id' tag below; may want to remove this later.
                FORM_FIELD_RUNTIME_ID => flush.runtime_id,
                FORM_FIELD_RECORDING_START => flush.start.utc.iso8601,
                FORM_FIELD_RECORDING_END => flush.finish.utc.iso8601,
                FORM_FIELD_TAGS => [
                  "#{FORM_FIELD_TAG_RUNTIME}:#{flush.language}",
                  "#{FORM_FIELD_TAG_RUNTIME_ID}:#{flush.runtime_id}",
                  "#{FORM_FIELD_TAG_RUNTIME_ENGINE}:#{flush.runtime_engine}",
                  "#{FORM_FIELD_TAG_RUNTIME_PLATFORM}:#{flush.runtime_platform}",
                  "#{FORM_FIELD_TAG_RUNTIME_VERSION}:#{flush.runtime_version}",
                  "#{FORM_FIELD_TAG_PID}:#{Process.pid}",
                  "#{FORM_FIELD_TAG_PROFILER_VERSION}:#{flush.profiler_version}",
                  # NOTE: Redundant w/ 'runtime'; may want to remove this later.
                  "#{FORM_FIELD_TAG_LANGUAGE}:#{flush.language}",
                  "#{FORM_FIELD_TAG_HOST}:#{flush.host}",
                  *flush
                    .tags
                    .reject { |tag_key| TAGS_TO_IGNORE_IN_TAGS_HASH.include?(tag_key) }
                    .map { |tag_key, tag_value| "#{tag_key}:#{tag_value}" }
                ],
                FORM_FIELD_DATA => pprof_file,
                FORM_FIELD_RUNTIME => flush.language,
                FORM_FIELD_FORMAT => FORM_FIELD_FORMAT_PPROF
              }

              # Add types
              form[FORM_FIELD_TYPES] = types.join(',')

              # Optional fields
              form[FORM_FIELD_TAGS] << "#{FORM_FIELD_TAG_SERVICE}:#{flush.service}" unless flush.service.nil?
              form[FORM_FIELD_TAGS] << "#{FORM_FIELD_TAG_ENV}:#{flush.env}" unless flush.env.nil?
              form[FORM_FIELD_TAGS] << "#{FORM_FIELD_TAG_VERSION}:#{flush.version}" unless flush.version.nil?

              form
            end

            def build_pprof(flush)
              pprof = encoder.encode(flush)

              # Wrap pprof as a gzipped file
              gzipped_data = Datadog::Utils::Compression.gzip(pprof.data)
              pprof_file = Datadog::Vendor::Multipart::Post::UploadIO.new(
                StringIO.new(gzipped_data),
                HEADER_CONTENT_TYPE_OCTET_STREAM,
                PPROF_DEFAULT_FILENAME
              )

              [pprof_file, [FORM_FIELD_TYPES_AUTO]]
            end
          end
        end
      end
    end
  end
end
