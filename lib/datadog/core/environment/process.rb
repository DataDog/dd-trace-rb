# frozen_string_literal: true

require_relative 'ext'
require_relative '../normalizer'

module Datadog
  module Core
    module Environment
      # Retrieves process level information such that it can be attached to various payloads
      module Process
        module_function

        # Returns the last segment of the working directory of the process
        # @return [String] the last segment of the working directory
        def entrypoint_workdir
          File.basename(Dir.pwd)
        end

        # Returns the entrypoint type of the process
        # @return [String] the type of the process, which is fixed in Ruby
        def entrypoint_type
          Environment::Ext::PROCESS_TYPE
        end

        # Returns the last segment of the base directory of the process
        # @return [String] the last segment of base directory of the script
        def entrypoint_name
          File.basename($0)
        end

        # Returns the last segment of the base directory of the process
        # @return [String] the last segment of the base directory of the script
        def entrypoint_basedir
          current_basedir = File.expand_path(File.dirname($0))
          normalized_basedir = current_basedir.tr(File::SEPARATOR, '/')
          normalized_basedir.delete_prefix('/')
        end

        # Normalize tag key and value using the Trace Agent's tag normalization logic
        # @param key [String] the original key
        # @param value [String] the original value
        # @return [String] normalized key:value pair
        def serialized_kv_helper(key, value)
          key = Normalizer.normalize(key)
          value = Normalizer.normalize(value)
          "#{key}:#{value}"
        end

        # This method returns a key/value part of serialized tags in the format of k1:v1,k2:v2,k3:v3
        # @return [String] comma-separated normalized key:value pairs
        def serialized
          return @serialized if defined?(@serialized)
          tags = []
          tags << serialized_kv_helper(Environment::Ext::TAG_ENTRYPOINT_WORKDIR, entrypoint_workdir) if entrypoint_workdir
          tags << serialized_kv_helper(Environment::Ext::TAG_ENTRYPOINT_NAME, entrypoint_name) if entrypoint_name
          tags << serialized_kv_helper(Environment::Ext::TAG_ENTRYPOINT_BASEDIR, entrypoint_basedir) if entrypoint_basedir
          tags << serialized_kv_helper(Environment::Ext::TAG_ENTRYPOINT_TYPE, entrypoint_type) if entrypoint_type
          @serialized = tags.join(',').freeze
        end
      end
    end
  end
end
