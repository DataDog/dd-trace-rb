# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Builder for collecting content parts inside a message block.
      #
      # Used via the block form of {Datadog::AIGuard.message}:
      #
      #   Datadog::AIGuard.message(role: :user) do |m|
      #     m.text("What's in this image?")
      #     m.image_url("https://example.com/img.png")
      #   end
      class ContentBuilder
        attr_reader :parts

        def initialize
          @parts = []
        end

        def text(text)
          @parts << ContentPart::Text.new(text)
        end

        def image_url(url)
          @parts << ContentPart::ImageURL.new(url)
        end
      end
    end
  end
end
