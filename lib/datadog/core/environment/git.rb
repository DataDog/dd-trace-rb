# frozen_string_literal: true

require_relative '../utils/url'

module Datadog
  module Core
    # Environment
    module Environment
      # Retrieves git repository information from the configuration
      module Git
        def self.git_repository_url(settings)
          Utils::Url.filter_basic_auth(settings.git.repository_url)
        end
      end
    end
  end
end
