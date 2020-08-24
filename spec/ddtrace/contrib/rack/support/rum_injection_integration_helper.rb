require 'json'
require 'zlib'

module RumInjectionHelpers
  def rum_injection_responses
    src = File.read('./spec/ddtrace/contrib/rack/support/rum_injection_responses.json.gz')
    io = StringIO.new(src)
    ungzipped_src = Zlib::GzipReader.new(io)
    tmp = ungzipped_src.read
    ungzipped_src.close
    readable_body = tmp
    JSON.parse(readable_body)
  end

  module_function :rum_injection_responses
end
