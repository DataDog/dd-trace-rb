require 'zlib'

module Datadog
  module Utils
    # Common database-related utility functions.
    module Compression
      module_function

      def gzip(string, level: nil, strategy: nil)
        sio = StringIO.new
        sio.binmode
        gz = Zlib::GzipWriter.new(sio, level, strategy)
        gz.write(string)
        gz.close
        sio.string
      end

      def gunzip(string, encoding = ::Encoding::ASCII_8BIT)
        sio = StringIO.new(string)
        gz = Zlib::GzipReader.new(sio, encoding: encoding)
        gz.read
      ensure
        gz && gz.close
      end
    end
  end
end
