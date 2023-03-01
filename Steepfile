target :appsec do
  signature 'sig'

  check 'lib/datadog/appsec'

  # TODO: disabled because of https://github.com/soutaro/steep/issues/701
  # check 'lib/datadog/kit'

  ignore 'lib/datadog/appsec/contrib'
  ignore 'lib/datadog/appsec/monitor'
  ignore 'lib/datadog/appsec/component.rb'

  library 'pathname', 'set'
  library 'cgi'
  library 'logger', 'monitor'
  library 'tsort'
  library 'json'

  # TODO: gem 'libddwaf'

  repo_path 'vendor/rbs'
  library 'ffi'
  library 'jruby'
  library 'gem'
  library 'rails'
  library 'sinatra'
end
