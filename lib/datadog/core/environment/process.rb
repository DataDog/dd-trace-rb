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
        # Returns a comma-separated string of normalized key:value pairs.
        # Includes svc.user or svc.auto based on whether the service was explicitly configured.
        # @return [String]
        def self.serialized
          tags.join(',').freeze
        end

        # Returns an array of normalized key:value pair strings.
        # Includes svc.user or svc.auto based on whether the service was explicitly configured.
        # @return [Array<String>]
        def self.tags
          tags = []

          workdir = TagNormalizer.normalize_process_value(entrypoint_workdir.to_s)
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_WORKDIR}:#{workdir}" unless workdir.empty?

          entry_name = TagNormalizer.normalize_process_value(entrypoint_name.to_s)
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_NAME}:#{entry_name}" unless entry_name.empty?

          basedir = TagNormalizer.normalize_process_value(entrypoint_basedir.to_s)
          tags << "#{Environment::Ext::TAG_ENTRYPOINT_BASEDIR}:#{basedir}" unless basedir.empty?

          tags << "#{Environment::Ext::TAG_ENTRYPOINT_TYPE}:#{TagNormalizer.normalize(entrypoint_type, remove_digit_start_char: false)}"

          rails_name = TagNormalizer.normalize_process_value(@rails_application_name.to_s)
          tags << "#{Environment::Ext::TAG_RAILS_APPLICATION}:#{rails_name}" unless rails_name.empty?

          if defined?(@service_user_configured)
            if @service_user_configured
              tags << "#{Environment::Ext::TAG_SVC_USER}:true"
            else
              svc = TagNormalizer.normalize_process_value(@service_name.to_s)
              tags << "#{Environment::Ext::TAG_SVC_AUTO}:#{svc}" unless svc.empty?
            end
          end

          tags.freeze
        end

        # Called via after_set on option :service in settings.rb whenever the service value changes.
        # @param name [String] the service name
        # @param user_configured [Boolean] whether the service was explicitly set by the user
        # @return [void]
        def self.set_service(name, user_configured:)
          @service_name = name
          @service_user_configured = user_configured
        end

        # Sets the rails application name from other places in code
        # @param name [String] the rails application name
        # @return [void]
        def self.rails_application_name=(name)
          @rails_application_name = name
        end

        # Returns the last segment of the working directory of the process
        # Example: /app/myapp -> myapp
        # @return [String] the last segment of the working directory
        def self.entrypoint_workdir
          return @entrypoint_workdir if defined?(@entrypoint_workdir)

          @entrypoint_workdir = File.basename(Dir.pwd)
        end

        # Returns the entrypoint type of the process
        # In Ruby, the entrypoint type is always 'script'
        # @return [String] the type of the process, which is fixed in Ruby
        def self.entrypoint_type
          Environment::Ext::PROCESS_TYPE
        end

        # Returns the basename of the script being run
        # Example 1: /bin/mybin -> mybin
        # Example 2: ruby /test/myapp.rb -> myapp.rb
        # @return [String] the basename of the script
        #
        # @note Determining true entrypoint name is rather complicated. This method
        # is the initial implementation but it does not produce optimal output in all cases.
        # For example, all Rails applications launched via `rails server` get `rails`
        # as their entrypoint name.
        # We might improve the behavior in the future if there is customer demand for it.
        def self.entrypoint_name
          return @entrypoint_name if defined?(@entrypoint_name)

          @entrypoint_name = File.basename($0)
        end

        # Returns the last segment of the directory containing the script
        # Example 1: /bin/mybin -> bin
        # Example 2: ruby /test/myapp.rb -> test
        # @return [String] the last segment of the base directory of the script
        #
        # @note As with entrypoint name, determining true entrypoint directory is complicated.
        # This method has an initial implementation that does not necessarily return good
        # results in all cases. For example, for Rails applications launched via `rails server`
        # the entrypoint basedir is `bin` which is not very helpful.
        # We might improve this in the future if there is customer demand.
        def self.entrypoint_basedir
          return @entrypoint_basedir if defined?(@entrypoint_basedir)

          @entrypoint_basedir = File.basename(File.expand_path(File.dirname($0)))
        end

        private_class_method :entrypoint_workdir, :entrypoint_type, :entrypoint_name, :entrypoint_basedir
      end
    end
  end
end
