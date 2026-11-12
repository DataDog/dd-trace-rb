# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # A wrapper around Seahorse::Client::RequestContext
        class ParsedContext
          PROVEN_ACCOUNT_ID_PROVIDERS = [
            "Aws::AssumeRoleCredentials",
            "Aws::AssumeRoleWebIdentityCredentials",
          ].freeze

          def initialize(context)
            @context = context
          end

          def safely(attr, fallback = nil)
            public_send(attr)
          rescue
            fallback
          end

          def resource
            "#{service}.#{operation}"
          end

          def operation
            context.operation_name
          end

          def params
            context.params
          end

          def http_response
            context.http_response
          end

          def status_code
            http_response.status_code
          end

          def http_method
            context.http_request.http_method
          end

          def region
            context.client.config.region
          end

          # The account id STS returned for the assumed role that signed this
          # request. Other providers take it from local configuration, and a
          # subclass can override `#refresh`, so only these exact classes count.
          #
          # `Aws::Plugins::Sign` prefers request-scoped credentials when a plugin
          # set them. `@credentials` is read directly because
          # `RefreshingCredentials#credentials` can refresh, which may call STS
          # and replace the identity that signed this request.
          def assumed_role_account_id
            provider = context[:sigv4_credentials] || context.client.config.credentials
            return unless PROVEN_ACCOUNT_ID_PROVIDERS.include?(provider.class.name)
            return unless provider.instance_variable_defined?(:@credentials)

            credentials = provider.instance_variable_get(:@credentials)
            credentials.account_id if credentials.respond_to?(:account_id)
          end

          def retry_attempts
            context.retries
          end

          def path
            context.http_request.endpoint.path
          end

          def host
            context.http_request.endpoint.host
          end

          private

          attr_reader :context

          def service
            context.client.class.to_s.split("::")[1].downcase
          end
        end
      end
    end
  end
end
