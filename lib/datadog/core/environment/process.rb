# frozen_string_literal: true

require_relative 'ext'
require_relative '../normalizer'

module Datadog
  module Core
    module Environment
      # Retrieves process level information such that it can be attached to various payloads
      module Process
        extend self

        # This method returns a key/value part of serialized tags in the format of k1:v1,k2:v2,k3:v3
        # @return [String] comma-separated normalized key:value pairs
        def serialized
          return @serialized if defined?(@serialized)
          tags = []
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_WORKDIR}:#{Normalizer.normalize(entrypoint_workdir, remove_digit_start_char: false)}" if entrypoint_workdir
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_NAME}:#{Normalizer.normalize(entrypoint_name, remove_digit_start_char: false)}" if entrypoint_name
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_BASEDIR}:#{Normalizer.normalize(entrypoint_basedir, remove_digit_start_char: false)}" if entrypoint_basedir
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_TYPE}:#{Normalizer.normalize(entrypoint_type, remove_digit_start_char: false)}" if entrypoint_type
          @serialized = tags.join(',').freeze
        end

        private

        # Returns the last segment of the working directory of the process
        # Example: /app/myapp -> myapp
        # @return [String] the last segment of the working directory
        def entrypoint_workdir
          File.basename(Dir.pwd)
        end

        # Returns the entrypoint type of the process
        # In Ruby, the entrypoint type is always 'script'
        # @return [String] the type of the process, which is fixed in Ruby
        def entrypoint_type
          Environment::Ext::PROCESS_TYPE
        end

        # Returns the last segment of the base directory of the process
        # Example 1: /bin/mybin -> mybin
        # Example 2: ruby /test/myapp.rb -> myapp
        # @return [String] the last segment of base directory of the script
        def entrypoint_name
          File.basename($0)
        end

        # Returns the last segment of the base directory of the process
        # Example 1: /bin/mybin -> bin
        # Example 2: ruby /test/myapp.js -> test
        # @return [String] the last segment of the base directory of the script
        def entrypoint_basedir
          File.basename(File.expand_path(File.dirname($0)))
        end
      end
    end
  end
end
