# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    module Configuration
      # Symbol Database configuration settings
      module Settings
        def self.extended(base)
          base = base.singleton_class unless base.is_a?(Class)
          add_settings!(base)
        end

        def self.add_settings!(base)
          base.class_eval do
            settings :symbol_database do
              option :enabled do |o|
                o.type :bool
                o.env 'DD_SYMBOL_DATABASE_UPLOAD_ENABLED'
                o.default true
              end

              option :force_upload do |o|
                o.type :bool
                o.env 'DD_SYMBOL_DATABASE_FORCE_UPLOAD'
                o.default false
              end

              option :includes do |o|
                o.type :array
                o.env 'DD_SYMBOL_DATABASE_INCLUDES'
                o.env_parser do |value|
                  value.to_s.split(',').map(&:strip).reject(&:empty?)
                end
                o.default []
              end
            end
          end
        end
      end
    end
  end
end
