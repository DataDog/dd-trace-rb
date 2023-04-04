require 'datadog/ci/spec_helper'
require 'datadog/ci/contrib/support/mode_helpers'
require 'datadog/tracing/contrib/support/spec_helper'

if defined?(Warning.ignore)
  # Caused by https://github.com/cucumber/cucumber-ruby/blob/47c8e2d7c97beae8541c895a43f9ccb96324f0f1/lib/cucumber/encoding.rb#L5-L6
  Gem.path.each do |path|
    Warning.ignore(/setting Encoding.default_external/, path)
    Warning.ignore(/setting Encoding.default_internal/, path)
  end
end
