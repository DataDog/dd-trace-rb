# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # Class to extract event information from the resource
        class Event
          UUID_REGEX = /^\h{8}-\h{4}-\h{4}-\h{4}-\h{12}$/.freeze

          attr_reader :user_id

          def initialize(resource, mode)
            @resource = resource
            @mode = mode
            @user_id = nil
            @email = nil
            @username = nil

            extract if @resource
          end

          def to_h
            return @event if defined?(@event)

            @event = {}
            @event[:email] = @email if @email
            @event[:username] = @username if @username
            @event
          end

          private

          def extract
            @user_id = @resource.id

            case @mode
            when AppSec::Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE
              @email = @resource.email
              @username = @resource.username
            when AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
              @user_id = nil unless @user_id && @user_id.to_s =~ UUID_REGEX
            else
              Datadog.logger.warn(
                "Invalid auto_user_instrumentation.mode: `#{@mode}`. " \
                "Supported modes are: #{AppSec::Configuration::Settings::AUTO_USER_INSTRUMENTATION_MODES.join(' | ')}."
              )
            end
          end
        end
      end
    end
  end
end
