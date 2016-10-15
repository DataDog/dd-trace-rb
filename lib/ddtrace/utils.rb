module Datadog
  # TODO[manu]: write docs
  module Utils
    # Return a span id
    def self.next_id
      rand(Datadog::Span::MAX_ID)
    end
  end
end
