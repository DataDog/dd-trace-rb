# frozen_string_literal: true

# typed: false

require 'erb'

module Datadog
  module Tracing
    module Contrib
      module Propagation
        module SqlComment
          class Comment
            def initialize(hash)
              @hash = hash
            end

            def to_s
              @string ||= begin
                ret = String.new

                @hash.each do |key, value|
                  next if value.nil?

                  value = ERB::Util.url_encode(value) # url encode
                  value.gsub!("'", "\'")              # escaping single quote

                  ret << "#{key}='#{value}'," # escape sql
                end

                ret.chop!

                "/*#{ret}*/"
              end
            end
          end
        end
      end
    end
  end
end
