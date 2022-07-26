# typed: true

require_relative '../../../../core/utils/compression'
require_relative '../../../../core/vendor/multipart-post/multipart/post/composite_read_io'
require_relative '../../../old_ext'
require_relative '../response'
require_relative '../../../../../ddtrace/transport/http/api/endpoint'

module Datadog
  module Profiling
    module Transport
      module HTTP
        module API
          # Datadog API endpoint for profiling
          class Endpoint < Datadog::Transport::HTTP::API::Endpoint
            include Profiling::OldExt::Transport::HTTP

            # These tags are read from the flush object (see below) directly and so we ignore any extra copies that
            # may come in the tags hash to avoid duplicates.
            TAGS_TO_IGNORE_IN_TAGS_HASH = %w[service env version].freeze
            private_constant :TAGS_TO_IGNORE_IN_TAGS_HASH

            attr_reader \
              :encoder

            def initialize(path, encoder = nil)
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
              flush = env.request
              pprof_file = build_pprof(flush)

              form = {
                FORM_FIELD_INTAKE_VERSION => '3', # Aka 1.3 intake format
                FORM_FIELD_RECORDING_START => flush.start.utc.iso8601,
                FORM_FIELD_RECORDING_END => flush.finish.utc.iso8601,
                FORM_FIELD_TAGS => flush.tags_as_array.map { |key, value| "#{key}:#{value}" },
                FORM_FIELD_PPROF_DATA => pprof_file,
                FORM_FIELD_FAMILY => 'ruby',
              }

              # May not be available/enabled
              form[FORM_FIELD_CODE_PROVENANCE_DATA] = build_code_provenance(flush) if flush.code_provenance_data

              form
            end

            def build_pprof(flush)
              gzipped_pprof_data = flush.pprof_data

              Core::Vendor::Multipart::Post::UploadIO.new(
                StringIO.new(gzipped_pprof_data),
                HEADER_CONTENT_TYPE_OCTET_STREAM,
                PPROF_DEFAULT_FILENAME
              )
            end

            def build_code_provenance(flush)
              gzipped_code_provenance = flush.code_provenance_data

              Core::Vendor::Multipart::Post::UploadIO.new(
                StringIO.new(gzipped_code_provenance),
                HEADER_CONTENT_TYPE_OCTET_STREAM,
                CODE_PROVENANCE_FILENAME,
              )
            end
          end
        end
      end
    end
  end
end
