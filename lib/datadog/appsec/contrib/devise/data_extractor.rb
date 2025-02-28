# frozen_string_literal: true

require_relative '../../anonymizer'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # An extractor of the data from Devise resources
        class DataExtractor
          def initialize(mode)
            @mode = mode
          end

          def extract_id(object)
            if object.is_a?(Hash)
              id = object[:id] || object['id'] || object[:uuid] || object['uuid']

              return transform(id)
            end

            id = object.id if object.respond_to?(:id)
            id ||= object.uuid if object.respond_to?(:uuid)

            scope = find_devise_scope(object)
            id = "#{scope}:#{id}" if scope

            transform(id)
          end

          def extract_login(object)
            if object.is_a?(Hash)
              login = object[:email] || object['email'] || object[:username] ||
                object['username'] || object[:login] || object['login']

              return transform(login)
            end

            login = object&.email if object.respond_to?(:email)
            login ||= object.username if object.respond_to?(:username)
            login ||= object.login if object.respond_to?(:login)

            transform(login)
          end

          private

          def find_devise_scope(object)
            return if ::Devise.mappings.count == 1

            ::Devise.mappings.each_value.find { |mapping| mapping.class_name == object.class.name }&.name
          end

          def transform(value)
            return if value.nil?
            return value.to_s unless anonymize?

            Anonymizer.anonymize(value.to_s)
          end

          def anonymize?
            @mode == AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
          end
        end
      end
    end
  end
end
