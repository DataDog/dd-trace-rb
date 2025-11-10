# frozen_string_literal: true
require_relative 'ext'

module Datadog
  module Core
    module Environment
      # Retrieves process level information
      module Process
        module_function

        def entrypoint_workdir
          File.basename(Dir.pwd)
        end

        def entrypoint_type
          Core::Environment::Ext::PROCESS_TYPE
        end

        def entrypoint_name
          File.basename($0.to_s)
        end

        def entrypoint_basedir
          current_basedir = File.expand_path(File.dirname($0.to_s))
          normalized_basedir = current_basedir.tr(File::SEPARATOR, '/')
          normalized_basedir.sub(%r{^/}, '')
        end

        def server_type
          'placeholder'
        end

        def formatted_process_tags_k1_v1
          return @formatted_process_tags_k1_v1 if defined?(@formatted_process_tags_k1_v1)
          tags = []
          tags << "#{Core::Environment::Ext::TAG_ENTRYPOINT_WORKDIR}:#{entrypoint_workdir}" if entrypoint_workdir
          tags << "#{Core::Environment::Ext::TAG_ENTRYPOINT_NAME}:#{entrypoint_name}" if entrypoint_name
          tags << "#{Core::Environment::Ext::TAG_ENTRYPOINT_BASEDIR}:#{entrypoint_basedir}" if entrypoint_basedir
          tags << "#{Core::Environment::Ext::TAG_ENTRYPOINT_TYPE}:#{entrypoint_type}" if entrypoint_type
          tags << "#{Core::Environment::Ext::TAG_SERVER_TYPE}:#{server_type}" if server_type
          @formatted_process_tags_k1_v1 = tags.join(',').freeze
        end
      end
    end
  end
end
