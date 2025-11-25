# frozen_string_literal: true

require_relative 'ext'
require_relative '../tag_normalizer'

module Datadog
  module Core
    module Environment
      # Retrieves process level information such that it can be attached to various payloads
      #
      # @api private
      module Process
        # This method returns a key/value part of serialized tags in the format of k1:v1,k2:v2,k3:v3
        # @return [String] comma-separated normalized key:value pairs
        def self.serialized
          return @serialized if defined?(@serialized)
          tags = []

          begin
            workdir = TagNormalizer.normalize(entrypoint_workdir.to_s, remove_digit_start_char: false)
            tags << "#{Environment::Ext::TAG_ENTRYPOINT_WORKDIR}:#{workdir}" unless workdir.empty?

            entry_name = TagNormalizer.normalize(entrypoint_name.to_s, remove_digit_start_char: false)
            tags << "#{Environment::Ext::TAG_ENTRYPOINT_NAME}:#{entry_name}" unless entry_name.empty?

            basedir = TagNormalizer.normalize(entrypoint_basedir.to_s, remove_digit_start_char: false)
            tags << "#{Environment::Ext::TAG_ENTRYPOINT_BASEDIR}:#{basedir}" unless basedir.empty?

            tags << "#{Environment::Ext::TAG_ENTRYPOINT_TYPE}:#{TagNormalizer.normalize(entrypoint_type, remove_digit_start_char: false)}"
          rescue => e
            Datadog.logger.debug("failed to get process_tags: #{e.class}: #{e}")
          end
          @serialized = tags.join(',').freeze
        end

        # Returns the last segment of the working directory of the process
        # Example: /app/myapp -> myapp
        # @return [String] the last segment of the working directory
        def self.entrypoint_workdir
          File.basename(Dir.pwd)
        end

        # Returns the entrypoint type of the process
        # In Ruby, the entrypoint type is always 'script'
        # @return [String] the type of the process, which is fixed in Ruby
        def self.entrypoint_type
          Environment::Ext::PROCESS_TYPE
        end

        # Returns the last segment of the base directory of the process
        # Example 1: /bin/mybin -> mybin
        # Example 2: ruby /test/myapp.rb -> myapp
        # @return [String] the last segment of base directory of the script
        def self.entrypoint_name
          File.basename($0)
        end

        # Returns the last segment of the base directory of the process
        # Example 1: /bin/mybin -> bin
        # Example 2: ruby /test/myapp.js -> test
        # @return [String] the last segment of the base directory of the script
        def self.entrypoint_basedir
          File.basename(File.expand_path(File.dirname($0)))
        end

        private_class_method :entrypoint_workdir, :entrypoint_type, :entrypoint_name, :entrypoint_basedir
      end
    end
  end
end
