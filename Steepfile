target :appsec do
  signature "sig"

  check "lib/datadog/appsec"
  ignore "lib/datadog/appsec/contrib"

  library "pathname", "set"
  library "cgi"
  library "logger", "monitor"
  library "tsort"
  library "json"

  #gem 'libddwaf'
end
