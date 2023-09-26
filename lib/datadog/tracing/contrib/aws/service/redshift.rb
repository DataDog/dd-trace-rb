# frozen_string_literal: true

require_relative './base'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Lambda tag handlers.
          class Redshift < Base
            def add_tags(span, params)
              cluster_identifier = params[:cluster_identifier]
              span.set_tag(Aws::Ext::TAG_CLUSTER_IDENTIFIER, cluster_identifier)
            end
          end
        end
      end
    end
  end
end
