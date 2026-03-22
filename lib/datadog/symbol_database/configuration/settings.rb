# frozen_string_literal: true

module Datadog
  module SymbolDatabase
    module Configuration
      # Settings for Symbol Database feature
      module Settings
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
                o.env 'DD_SYMBOL_DATABASE_INCLUDES'
                o.env_parser do |value|
                  value&.split(',')&.map(&:strip)&.reject(&:empty?)
                end
                o.type :array
                o.default []
              end
            end
          end
        end
      end
    end
  end
end
