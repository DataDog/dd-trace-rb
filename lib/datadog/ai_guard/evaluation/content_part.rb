# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Namespace for content part types used in multi-modal messages.
      module ContentPart
        # A text content part.
        class Text
          attr_reader :text

          def initialize(text)
            @text = text
          end

          def type
            :text
          end
        end

        # An image URL content part. Accepts an absolute URL or a base64 data URI.
        class ImageURL
          attr_reader :url

          def initialize(url)
            @url = url
          end

          def type
            :image_url
          end
        end
      end
    end
  end
end
