# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Base class for all AWS service-specific tag handlers.
          class Base
            def add_tags(span, params)
            end

            private

            # Emits a resolved target-identity name tag, skipping an empty
            # name.
            #
            # The new `aws.*.name` tags preserve no prior behavior, so an empty
            # one would publish a target identity the request never named. The
            # legacy name tags are written unconditionally by each handler
            # because `peer.service` resolution depends on it.
            def set_resolved_name(span, key, name)
              return if name.nil? || name == ""

              span.set_tag(key, name)
            end
          end
        end
      end
    end
  end
end
