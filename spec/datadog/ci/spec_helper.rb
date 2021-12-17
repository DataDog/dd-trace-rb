# typed: strict
require 'datadog/ci'
require 'ddtrace/contrib/support/spec_helper'

if defined?(Warning)
  # Caused by https://github.com/cucumber/cucumber-ruby/blob/47c8e2d7c97beae8541c895a43f9ccb96324f0f1/lib/cucumber/encoding.rb#L5-L6
  Warning.ignore(/setting Encoding.default_external/, GEMS_PATH)
  Warning.ignore(/setting Encoding.default_internal/, GEMS_PATH)
end
