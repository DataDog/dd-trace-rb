# frozen_string_literal: true
require_relative 'ext'
require_relative '../normalizer'

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
          File.basename($0)
        end

        def entrypoint_basedir
          current_basedir = File.expand_path(File.dirname($0))
          normalized_basedir = current_basedir.tr(File::SEPARATOR, '/')
          normalized_basedir.delete_prefix!('/')
        end

        # Normalize tag key and value using the Datadog Agent's tag normalization logic
        def serialized_kv_helper(key, value)
          key = Core::Normalizer.normalize(key)
          value = Core::Normalizer.normalize(value)
          "#{key}:#{value}"
        end

        # This method returns a key/value part of serialized tags in the format of k1:v1,k2:v2,k3:v3
        def serialized
          return @serialized if defined?(@serialized)
          tags = []
          tags << serialized_kv_helper(Core::Environment::Ext::TAG_ENTRYPOINT_WORKDIR, entrypoint_workdir) if entrypoint_workdir
          tags << serialized_kv_helper(Core::Environment::Ext::TAG_ENTRYPOINT_NAME, entrypoint_name) if entrypoint_name
          tags << serialized_kv_helper(Core::Environment::Ext::TAG_ENTRYPOINT_BASEDIR, entrypoint_basedir) if entrypoint_basedir
          tags << serialized_kv_helper(Core::Environment::Ext::TAG_ENTRYPOINT_TYPE, entrypoint_type) if entrypoint_type
          @serialized = tags.join(',').freeze
        end
      end
    end
  end
end
