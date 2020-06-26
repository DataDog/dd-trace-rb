#--
# Copyright (c) 2007-2012 Nick Sieger.
# See the file README.txt included with the distribution for
# software license details.
#++

require 'net/http'
require 'stringio'
require 'cgi'
require 'ddtrace/vendor/multipart-post/multipart/post/parts'
require 'ddtrace/vendor/multipart-post/multipart/post/composite_read_io'
require 'ddtrace/vendor/multipart-post/multipart/post/multipartable'

module Datadog
  module Vendor
    module Net
      class HTTP
        class Put
          class Multipart < ::Net::HTTP::Put
            include ::Datadog::Vendor::Multipart::Post::Multipartable
          end
        end

        class Post
          class Multipart < ::Net::HTTP::Post
            include ::Datadog::Vendor::Multipart::Post::Multipartable
          end
        end
      end
    end
  end
end
