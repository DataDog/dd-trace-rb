target :appsec do
  signature "sig"

  check "lib/datadog/appsec"
  ignore "lib/datadog/appsec/contrib"

  library "pathname", "set"
  library "cgi"
  library "logger", "monitor"
  library "tsort"
  library "json"

  # TODO: gem 'libddwaf'

  repo_path "vendor/rbs"
  library "ffi"
  library "jruby"
  library "gem"
  library "rails"
  library "sinatra"
end
