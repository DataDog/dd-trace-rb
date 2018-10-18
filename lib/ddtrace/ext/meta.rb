require 'ddtrace/version'

module Datadog
  module Ext
    module Meta
      LANG = 'ruby'.freeze
      LANG_INTERPRETER = begin
        if Gem::Version.new(RUBY_VERSION) > Gem::Version.new('1.9')
          (RUBY_ENGINE + '-' + RUBY_PLATFORM)
        else
          ('ruby-' + RUBY_PLATFORM)
        end
      end.freeze
      LANG_VERSION = RUBY_VERSION
      TRACER_VERSION = Datadog::VERSION::STRING
    end
  end
end
