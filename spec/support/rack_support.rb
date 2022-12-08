module RackSupport
  module_function

  # Converts `header` to `HTTP_HEADER`, the same
  # way Rack converts HTTP Header names to Rack `env` keys.
  def header_to_rack(header)
    "http-#{header}".upcase!.tr('-', '_')
  end
end
