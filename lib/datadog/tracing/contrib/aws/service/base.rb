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

            # Emits a resolved target-identity name tag, unless there is no
            # name to report.
            #
            # The legacy top-level name tags (`tablename`, `streamname`,
            # `topicname`) are written unconditionally, which is pre-existing
            # behavior `peer.service` resolution depends on: a request whose
            # target cannot be resolved leaves them empty rather than absent.
            # The `aws.*.name` tags are new, so there is no behavior to
            # preserve, and an empty one would publish a target identity the
            # request never named.
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
