# frozen_string_literal: true
# typed: true

require_relative 'fetcher'
require_relative '../../../distributed/propagation'
require_relative '../../../distributed/b3'
require_relative '../../../distributed/b3_single'
require_relative '../../../distributed/datadog'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # Extracts and injects propagation through HTTP headers.
          class Propagation < Tracing::Distributed::Propagation
            def initialize
              super(
                propagation_styles: {
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3 =>
                    Tracing::Distributed::B3.new(fetcher: Fetcher),
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER =>
                    Tracing::Distributed::B3Single.new(fetcher: Fetcher),
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG =>
                    Tracing::Distributed::Datadog.new(fetcher: Fetcher)
                })
            end
          end
        end
      end
    end
  end
end
