require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/analytics_examples"
require "datadog/tracing/contrib/integration_examples"
require "datadog/tracing/contrib/environment_service_name_examples"
require "datadog/tracing/contrib/span_attribute_schema_examples"
require "datadog/tracing/contrib/peer_service_configuration_examples"
require "datadog/tracing/contrib/svc_src_examples"

require "aws-sdk"
require "tempfile"

require "datadog/tracing"
require "datadog/tracing/metadata/ext"
require "datadog"
require "datadog/tracing/contrib/aws/patcher"

RSpec.describe "AWS instrumentation" do
  let(:configuration_options) { {} }
  let(:server_error_statuses) { nil }

  # The stubbed-response examples produce exactly one span, so they use the
  # `span` helper. The examples that let the request go over HTTP cannot: when
  # another spec in the same process has already patched `net/http`, that
  # integration traces the same request and a second span appears. Picking the
  # AWS span by name keeps those examples independent of what else ran first.
  let(:aws_span) { spans.find { |s| s.name == Datadog::Tracing::Contrib::Aws::Ext::SPAN_COMMAND } }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :aws, configuration_options
      c.tracing.http_error_statuses.server = server_error_statuses if server_error_statuses
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:aws].reset_configuration!
    example.run
    Datadog.registry[:aws].reset_configuration!
  end

  context "with a core AWS SDK client" do
    before { hide_const("Aws::S3") }

    let(:client) { ::Aws::STS::Client.new(stub_responses: responses) } # STS is part of aws-sdk-core

    describe "#get_access_key_info" do
      subject!(:get_access_key_info) { client.get_access_key_info(access_key_id: "dummy") }
      let(:responses) { {get_access_key_info: {account: "test account"}} }

      it_behaves_like "analytics for integration" do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like "measured span for integration"
      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "tags _dd.svc_src", "aws"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "sts.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span).not_to have_error
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sts.get_access_key_info")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("get_access_key_info")
        expect(span.get_tag("aws.region")).to eq("us-stubbed-1")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("sts.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sts.us-stubbed-1.amazonaws.com")
      end

      it "returns an unmodified response" do
        expect(get_access_key_info.account).to eq("test account")
      end
    end
  end

  context "with an S3 client" do
    let(:client) { ::Aws::S3::Client.new(stub_responses: responses) }

    describe "#list_buckets" do
      subject!(:list_buckets) { client.list_buckets }

      let(:responses) do
        {list_buckets: {buckets: [{name: "bucket1"}]}}
      end

      it_behaves_like "analytics for integration" do
        let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_ENABLED }
        let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Aws::Ext::ENV_ANALYTICS_SAMPLE_RATE }
      end

      it_behaves_like "measured span for integration"
      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "s3.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("s3.list_buckets")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("list_buckets")
        expect(span.get_tag("aws.region")).to eq("us-stubbed-1")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("s3")
        expect(span.get_tag("path")).to eq("/")
        expect(span.get_tag("host")).to eq("s3.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("GET")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("s3.us-stubbed-1.amazonaws.com")
      end

      it "returns an unmodified response" do
        expect(list_buckets.buckets.map(&:name)).to eq(["bucket1"])
      end
    end

    context "when the client runs and the API returns an error" do
      subject(:list_buckets) { client.list_buckets }

      let(:client) { ::Aws::S3::Client.new(stub_responses: true) }

      context "when the error status code is 500" do
        before do
          client.stub_responses(
            :list_buckets,
            status_code: 500,
            body: "test body with 500 error",
            headers: {}
          )
        end

        it "generates an errored span" do
          expect do
            list_buckets
          end.to raise_error(Aws::S3::Errors::Http500Error)
          # The Http500Error instance does not contain the body of the
          # response.
          expect(span).to have_error
          expect(span.tags["http.status_code"]).to eq("500")
        end
      end

      context "when the error status code is 404" do
        before do
          client.stub_responses(
            :list_buckets,
            status_code: 404,
            body: "test body with 404 error",
            headers: {}
          )
        end

        it " does not generates an errored span" do
          expect do
            list_buckets
          end.to raise_error(Aws::S3::Errors::NotFound)
          expect(span).not_to have_error
          expect(span.tags["http.status_code"]).to eq("404")
        end

        context "when the server error statuses are configured to include 404" do
          let(:server_error_statuses) { 400..599 }

          it "generates an errored span" do
            expect do
              list_buckets
            end.to raise_error(Aws::S3::Errors::NotFound)
            expect(span).to have_error
            expect(span.tags["http.status_code"]).to eq("404")
          end
        end
      end
    end

    describe "#list_objects" do
      subject!(:list_objects) { client.list_objects(bucket: "bucketname", max_keys: 2) }

      let(:responses) do
        {list_objects: {}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "bucketname" }
        let(:peer_service_source) { "bucketname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("s3.list_objects")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("list_objects")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("s3")
        expect(span.get_tag("bucketname")).to eq("bucketname")
        expect(span.get_tag("path")).to eq("/")
        expect(span.get_tag("host")).to eq("bucketname.s3.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("GET")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("bucketname.s3.us-stubbed-1.amazonaws.com")
      end
    end

    describe "S3::Presigner" do
      let(:presigner) { ::Aws::S3::Presigner.new(client: client) }

      describe "#presigned_url" do
        subject!(:presign) { presigner.presigned_url(:get_object, bucket: "bucket", key: "key") }

        # presigned_url returns a string instead of a Seahorse object, so it does not accept
        # object stubbing like other S3 methods. We simply tell it to enable stubbing and it
        # will return a stubbed URL without hitting the remote.
        let(:responses) { {presigned_url: true} }

        it "does not instrument presign as an HTTP request" do
          presign

          expect(spans).to be_empty
        end

        it "returns an unmodified response" do
          expect(presign).to start_with("https://bucket.s3.us-stubbed-1.amazonaws.com/key")
        end
      end
    end

    describe "bucket owner condition" do
      subject(:get_object) do
        client.get_object(bucket: "my-bucket", key: "my-key", **owner_params)
      end

      let(:client) { ::Aws::S3::Client.new(stub_responses: true) }
      let(:owner_params) { {expected_bucket_owner: "123456789012"} }

      context "when the response succeeds" do
        before { client.stub_responses(:get_object, status_code: 200, body: "data", headers: {}) }

        it "tags the verified bucket owner" do
          get_object

          expect(span.get_tag("aws_account")).to eq("123456789012")
          expect(span.get_tag("bucketname")).to eq("my-bucket")
          expect(span.get_tag("http.status_code")).to eq("200")
        end
      end

      context "when S3 rejects the expected bucket owner" do
        before { client.stub_responses(:get_object, status_code: 403, body: "", headers: {}) }

        it "does not tag an account" do
          expect { get_object }.to raise_error(::Aws::S3::Errors::Forbidden)

          expect(span.get_tag("aws_account")).to be_nil
          expect(span.get_tag("bucketname")).to eq("my-bucket")
          expect(span.get_tag("http.status_code")).to eq("403")
        end
      end

      context "when the request fails for an unrelated reason" do
        before { client.stub_responses(:get_object, status_code: 500, body: "", headers: {}) }

        it "does not tag an account" do
          expect { get_object }.to raise_error(::Aws::S3::Errors::Http500Error)

          expect(span.get_tag("aws_account")).to be_nil
        end
      end

      context "without the expected bucket owner parameter" do
        let(:owner_params) { {} }

        before { client.stub_responses(:get_object, status_code: 200, body: "data", headers: {}) }

        it "does not tag an account" do
          get_object

          expect(span.get_tag("aws_account")).to be_nil
        end
      end

      context "over HTTP against an AWS endpoint", webmock: true do
        before { WebMock.disable_net_connect! }
        after { WebMock.allow_net_connect! }

        let(:client) do
          ::Aws::S3::Client.new(
            region: "us-east-1",
            credentials: ::Aws::Credentials.new("akid", "secret"),
            force_path_style: true,
            retry_limit: 0
          )
        end

        let(:url) { "https://s3.amazonaws.com/my-bucket/my-key" }

        context "when S3 returns the object" do
          before { stub_request(:get, url).to_return(status: 200, body: "data") }

          it "tags the verified bucket owner" do
            get_object

            expect(
              a_request(:get, url).with(headers: {"x-amz-expected-bucket-owner" => "123456789012"})
            ).to have_been_made

            expect(aws_span.get_tag("aws_account")).to eq("123456789012")
            expect(aws_span.get_tag("http.status_code")).to eq("200")
          end
        end

        context "when S3 denies the request" do
          before do
            stub_request(:get, url).to_return(
              status: 403,
              body: "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
            )
          end

          it "does not tag an account" do
            expect { get_object }.to raise_error(::Aws::S3::Errors::AccessDenied)

            expect(aws_span.get_tag("aws_account")).to be_nil
            expect(aws_span.get_tag("http.status_code")).to eq("403")
          end
        end
      end

      # An S3-compatible service accepts `x-amz-expected-bucket-owner` and
      # ignores it, so a 200 from one is not evidence about an AWS account.
      context "over HTTP against an S3-compatible endpoint", webmock: true do
        before { WebMock.disable_net_connect! }
        after { WebMock.allow_net_connect! }

        let(:client) do
          ::Aws::S3::Client.new(
            region: "us-east-1",
            credentials: ::Aws::Credentials.new("akid", "secret"),
            endpoint: endpoint,
            force_path_style: true,
            retry_limit: 0
          )
        end

        {
          "a LocalStack endpoint" => "http://localhost:4566",
          "a MinIO endpoint" => "http://minio.internal:9000",
          "a self-hosted gateway" => "https://s3.storage.example.com",
          "an AWS lookalike domain" => "https://s3.us-east-1.amazonaws.com.example.net",
        }.each do |description, configured_endpoint|
          context "such as #{description}" do
            let(:endpoint) { configured_endpoint }
            let(:url) { "#{configured_endpoint}/my-bucket/my-key" }

            before { stub_request(:get, url).to_return(status: 200, body: "data") }

            it "sends the header but does not tag an account" do
              get_object

              expect(
                a_request(:get, url).with(headers: {"x-amz-expected-bucket-owner" => "123456789012"})
              ).to have_been_made

              expect(aws_span.get_tag("aws_account")).to be_nil
              expect(aws_span.get_tag("bucketname")).to eq("my-bucket")
              expect(aws_span.get_tag("http.status_code")).to eq("200")
            end
          end
        end
      end
    end
  end

  context "with an SQS client" do
    let(:client) { ::Aws::SQS::Client.new(stub_responses: responses) }

    describe "#send_message" do
      subject!(:send_message) do
        client.send_message(
          {
            queue_url: "https://sqs.us-stubbed-1.amazonaws.com/123456789012/MyQueueName",
            message_body: "Hello, world!",
          }
        )
      end

      let(:responses) do
        {send_message: {
          md5_of_message_body: "msg body",
          md5_of_message_attributes: "msg attributes",
          md5_of_message_system_attributes: "message system attributes",
          message_id: "123",
          sequence_number: "456",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyQueueName" }
        let(:peer_service_source) { "queuename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sqs.send_message")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("send_message")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("sqs")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("queuename")).to eq("MyQueueName")
        expect(span.get_tag("path")).to eq("/123456789012/MyQueueName")
        expect(span.get_tag("host")).to eq("sqs.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sqs.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#send_message_batch" do
      subject!(:send_message_batch) do
        client.send_message_batch(
          {
            queue_url: "https://sqs.us-stubbed-1.amazonaws.com/123456789012/MyQueueName",
            entries: [ # required
              {
                id: "String", # required
                message_body: "String", # required
                delay_seconds: 1,
                message_attributes: {
                  "String" => {
                    string_value: "String",
                    binary_value: "data",
                    string_list_values: ["String"],
                    binary_list_values: ["data"],
                    data_type: "String", # required
                  },
                },
                message_system_attributes: {
                  "AWSTraceHeader" => {
                    string_value: "String",
                    binary_value: "data",
                    string_list_values: ["String"],
                    binary_list_values: ["data"],
                    data_type: "String", # required
                  },
                },
                message_deduplication_id: "String",
                message_group_id: "String",
              },
            ],
          }
        )
      end

      let(:responses) do
        {send_message_batch: {
          successful: [],
          failed: [],
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyQueueName" }
        let(:peer_service_source) { "queuename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sqs.send_message_batch")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("send_message_batch")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("sqs")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("queuename")).to eq("MyQueueName")
        expect(span.get_tag("path")).to eq("/123456789012/MyQueueName")
        expect(span.get_tag("host")).to eq("sqs.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sqs.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#get_queue_url" do
      subject!(:get_queue_url) do
        client.get_queue_url(
          {
            queue_name: "MyQueueName",
            queue_owner_aws_account_id: "1234",
          }
        )
      end

      let(:responses) do
        {get_queue_url: {
          queue_url: "myQueueURL",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyQueueName" }
        let(:peer_service_source) { "queuename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sqs.get_queue_url")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("get_queue_url")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("sqs")
        expect(span.get_tag("queuename")).to eq("MyQueueName")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("sqs.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sqs.us-stubbed-1.amazonaws.com")
      end
    end
  end

  context "with an SNS client" do
    let(:client) { ::Aws::SNS::Client.new(stub_responses: responses) }

    describe "#publish" do
      subject!(:publish) do
        client.publish(
          {
            topic_arn: "arn:aws:sns:us-west-2:123456789012:my-topic-name",
            message: "Hello, world!",
          }
        )
      end

      let(:responses) do
        {publish: {
          message_id: "1234",
          sequence_number: "5678",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-topic-name" }
        let(:peer_service_source) { "topicname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sns.publish")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("publish")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("sns")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("topicname")).to eq("my-topic-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("sns.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sns.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#create_topic" do
      subject!(:create_topic) do
        client.create_topic(
          {
            name: "topicName", # required
            attributes: {
              "attributeName" => "attributeValue",
            },
            tags: [
              {
                key: "TagKey", # required
                value: "TagValue", # required
              },
            ],
          }
        )
      end

      let(:responses) do
        {create_topic: {}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "topicName" }
        let(:peer_service_source) { "topicname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("sns.create_topic")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("create_topic")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("sns")
        expect(span.get_tag("topicname")).to eq("topicName")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("sns.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("sns.us-stubbed-1.amazonaws.com")
      end
    end
  end

  context "with an dynamodb client" do
    let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses) }

    # A real STS client with a stubbed response, so the providers below derive
    # their account id the production way: from the `AssumedRoleUser.Arn` that
    # STS returned.
    def stub_sts_client(operation, account_id: "999988887777")
      ::Aws::STS::Client.new(
        region: "us-east-1",
        credentials: ::Aws::Credentials.new("stub-akid", "stub-secret"),
        stub_responses: true
      ).tap do |sts|
        sts.stub_responses(
          operation,
          credentials: {
            access_key_id: "ASIAEXAMPLE",
            secret_access_key: "session-secret",
            session_token: "session-token",
            expiration: Time.now + 3600,
          },
          assumed_role_user: {
            assumed_role_id: "AROAEXAMPLE:example-session",
            arn: "arn:aws:sts::#{account_id}:assumed-role/example-role/example-session",
          }
        )
      end
    end

    def assume_role_provider(account_id: "999988887777")
      ::Aws::AssumeRoleCredentials.new(
        client: stub_sts_client(:assume_role, account_id: account_id),
        role_arn: "arn:aws:iam::#{account_id}:role/example-role",
        role_session_name: "example-session"
      )
    end

    # Owner tagging is optional, so a failure in it must not cost the span any
    # of the tags the instrumentation is actually responsible for.
    describe "owner tagging failure isolation" do
      subject(:get_item) { client.get_item(table_name: "my-table-name", key: {id: "1234"}) }

      let(:responses) { {get_item: {item: {"Artist" => "Acme Band"}}} }
      let(:handler) { Datadog::Tracing::Contrib::Aws::SERVICE_HANDLERS["dynamodb"] }

      before { allow(handler).to receive(:add_owner_tags).and_raise("owner tagging blew up") }

      it "keeps every mandatory tag and leaves the call unaffected" do
        expect(get_item.item).to eq("Artist" => "Acme Band")

        expect(handler).to have_received(:add_owner_tags)
        expect(span.get_tag("aws_account")).to be_nil

        expect(span.get_tag("tablename")).to eq("my-table-name")
        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws_service")).to eq("dynamodb")
        expect(span.get_tag("aws.operation")).to eq("get_item")
        expect(span.get_tag("aws.region")).to eq("us-stubbed-1")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("dynamodb.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("dynamodb.us-stubbed-1.amazonaws.com")
        expect(span).not_to have_error
      end
    end

    describe "#get_item" do
      subject!(:get_item) { client.get_item(table_name: "my-table-name", key: {id: "1234"}) }

      let(:responses) do
        {get_item: {
          item: {
            "AlbumTitle" => "Songs About Life",
            "Artist" => "Acme Band",
            "SongTitle" => "Happy Day",
          },
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-table-name" }
        let(:peer_service_source) { "tablename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("dynamodb.get_item")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("get_item")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("dynamodb")
        expect(span.get_tag("tablename")).to eq("my-table-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("dynamodb.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("dynamodb.us-stubbed-1.amazonaws.com")
      end
    end

    describe "owner account identity" do
      subject!(:get_item) { client.get_item(table_name: table_name, key: {id: "1234"}) }

      let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses, credentials: credentials) }
      let(:responses) { {get_item: {item: {"Artist" => "Acme Band"}}} }
      let(:table_name) { "my-table-name" }
      let(:credentials) { assume_role_provider }

      # STS is instrumented too, so building an assume-role provider emits its
      # own span. Pick the DynamoDB one rather than assume there is only one.
      let(:span) { spans.find { |candidate| candidate.get_tag("aws_service") == "dynamodb" } }

      context "with an AssumeRole provider" do
        it "tags the assumed-role account" do
          expect(span.get_tag("aws_account")).to eq("999988887777")
          expect(span.get_tag("tablename")).to eq("my-table-name")
          expect(span).not_to have_error
        end
      end

      context "with an AssumeRoleWithWebIdentity provider" do
        let(:token_file) do
          file = Tempfile.new("web-identity-token")
          file.write("stub-oidc-token")
          file.flush
          file
        end

        let(:credentials) do
          ::Aws::AssumeRoleWebIdentityCredentials.new(
            client: stub_sts_client(:assume_role_with_web_identity, account_id: "111122223333"),
            role_arn: "arn:aws:iam::111122223333:role/example-role",
            role_session_name: "example-session",
            web_identity_token_file: token_file.path
          )
        end

        after { token_file.close! }

        it "tags the assumed-role account" do
          expect(span.get_tag("aws_account")).to eq("111122223333")
          expect(span.get_tag("tablename")).to eq("my-table-name")
        end
      end

      # The account id these report came from local configuration, not from
      # AWS, so it is not evidence of who owns the table.
      context "with static credentials carrying an account id" do
        let(:credentials) { ::Aws::Credentials.new("akid", "secret", nil, account_id: "123456789012") }

        it "does not tag an account" do
          expect(span.get_tag("aws_account")).to be_nil
          expect(span.get_tag("tablename")).to eq("my-table-name")
        end
      end

      context "with static credentials carrying no account id" do
        let(:credentials) { ::Aws::Credentials.new("akid", "secret") }

        it "does not tag an account" do
          expect(span.get_tag("aws_account")).to be_nil
          expect(span.get_tag("tablename")).to eq("my-table-name")
        end
      end

      context "with a custom credential provider carrying an account id" do
        let(:credentials) do
          provider_class = Class.new do
            include ::Aws::CredentialProvider

            def initialize(credentials)
              @credentials = credentials
            end
          end

          provider_class.new(
            ::Aws::Credentials.new("akid", "secret", "session-token", account_id: "999988887777")
          )
        end

        it "does not tag an account" do
          expect(span.get_tag("aws_account")).to be_nil
        end
      end

      context "with an assume-role account id that is malformed" do
        let(:credentials) { assume_role_provider(account_id: "12345") }

        it "does not tag an account" do
          expect(span.get_tag("aws_account")).to be_nil
        end
      end

      context "with a table ARN" do
        let(:table_name) { "arn:aws:dynamodb:us-stubbed-1:999988887777:table/my-table-name" }

        it "does not tag an account" do
          expect(span.get_tag("aws_account")).to be_nil
          expect(span.get_tag("tablename")).to eq(table_name)
        end
      end

      context "when a second credential lookup would fail" do
        let(:credentials) do
          provider = assume_role_provider
          # Nothing after the provider is built may resolve credentials again,
          # neither the signer nor span annotation, so make any further STS
          # call raise: a second lookup then shows up as a missing tag.
          allow(provider.client).to receive(:assume_role)
            .and_raise(::Aws::Errors::MissingCredentialsError)
          provider
        end

        it "tags the resolved account and never looks the credentials up again" do
          expect(get_item.item).to eq("Artist" => "Acme Band")
          expect(span.get_tag("aws_account")).to eq("999988887777")
          expect(span).not_to have_error
          expect(credentials.client).not_to have_received(:assume_role)
        end
      end

      context "when reading the resolved credentials raises" do
        let(:credentials) do
          provider = assume_role_provider
          allow(provider).to receive(:instance_variable_defined?)
            .and_raise(::Aws::Errors::MissingCredentialsError)
          provider
        end

        it "completes the call and does not tag an account" do
          expect(get_item.item).to eq("Artist" => "Acme Band")
          expect(span.get_tag("aws_account")).to be_nil
          expect(span).not_to have_error
        end
      end
    end

    # A bare table name only names a table in the signing account once AWS has
    # resolved it there, so a request that failed, or one that never reached
    # AWS, proves nothing about who owns anything.
    describe "owner account identity on a response that proves nothing" do
      subject(:get_item) { client.get_item(table_name: "my-table-name", key: {id: "1234"}) }

      let(:credentials) { assume_role_provider }
      let(:span) { spans.find { |candidate| candidate.get_tag("aws_service") == "dynamodb" } }

      context "when the table does not exist in the signing account" do
        let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses, credentials: credentials) }
        let(:responses) { {get_item: "ResourceNotFoundException"} }

        it "does not tag an account" do
          expect { get_item }.to raise_error(::Aws::DynamoDB::Errors::ResourceNotFoundException)

          expect(span.get_tag("aws_account")).to be_nil
          expect(span.get_tag("tablename")).to eq("my-table-name")
        end
      end

      # DynamoDB Local and LocalStack accept the same bare table name and
      # resolve it in a local store that has no AWS account behind it, so a 200
      # from one of those is not evidence about any AWS account.
      context "over HTTP against a DynamoDB-compatible endpoint", webmock: true do
        let(:endpoint) { "http://localhost:8000" }
        let(:url) { "#{endpoint}/" }
        let(:client) do
          ::Aws::DynamoDB::Client.new(
            region: "us-east-1",
            credentials: credentials,
            endpoint: endpoint,
            retry_limit: 0
          )
        end

        before do
          WebMock.disable_net_connect!
          stub_request(:post, url).to_return(
            status: 200,
            body: '{"Item":{"Artist":{"S":"Acme Band"}}}',
            headers: {"Content-Type" => "application/x-amz-json-1.0"}
          )
        end

        after { WebMock.allow_net_connect! }

        it "does not tag an account" do
          expect(get_item.item).to eq("Artist" => "Acme Band")

          expect(a_request(:post, url)).to have_been_made
          expect(aws_span.get_tag("aws_account")).to be_nil
          expect(aws_span.get_tag("tablename")).to eq("my-table-name")
          expect(aws_span.get_tag("host")).to eq("localhost")
          expect(aws_span.get_tag("http.status_code")).to eq("200")
        end
      end

      # The same request against the real endpoint is tagged, which is what
      # says the endpoint check is the only thing holding the case above back.
      context "over HTTP against an AWS endpoint", webmock: true do
        # DynamoDB uses account-based endpoint routing when the credentials
        # carry an account id, which puts it in the host
        # (`<account>.ddb.<region>.amazonaws.com`) instead of using
        # `dynamodb.<region>.amazonaws.com`. Either host is AWS, and which one
        # the SDK picks depends on its version, so this matches on the shape.
        let(:url) { %r{\Ahttps://[a-z0-9.-]+\.amazonaws\.com/\z} }
        let(:client) do
          ::Aws::DynamoDB::Client.new(
            region: "us-east-1",
            credentials: credentials,
            retry_limit: 0
          )
        end

        before do
          WebMock.disable_net_connect!
          stub_request(:post, url).to_return(
            status: 200,
            body: '{"Item":{"Artist":{"S":"Acme Band"}}}',
            headers: {"Content-Type" => "application/x-amz-json-1.0"}
          )
        end

        after { WebMock.allow_net_connect! }

        it "tags the assumed-role account" do
          expect(get_item.item).to eq("Artist" => "Acme Band")

          expect(aws_span.get_tag("aws_account")).to eq("999988887777")
          expect(aws_span.get_tag("host")).to end_with(".amazonaws.com")
          expect(aws_span.get_tag("http.status_code")).to eq("200")
        end
      end
    end
  end

  context "with an kinesis client" do
    let(:client) { ::Aws::Kinesis::Client.new(stub_responses: responses) }

    describe "#put_record" do
      subject!(:put_record) do
        client.put_record(
          stream_name: "my-stream-name",
          partition_key: "parition-1",
          data: "Hello world!"
        )
      end

      let(:responses) do
        {put_record: {
          shard_id: "1234",
          sequence_number: "5678",
          encryption_type: "NONE",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-stream-name" }
        let(:peer_service_source) { "streamname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("kinesis.put_record")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("put_record")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("kinesis")
        expect(span.get_tag("streamname")).to eq("my-stream-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("kinesis.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("kinesis.us-stubbed-1.amazonaws.com")
      end
    end

    # aws-sdk >= (3.1.0)->aws-sdk-kinesis >= (1.45.0) resolves to a different host name
    describe "#describe_stream_consumer" do
      subject!(:describe_stream_consumer) do
        client.describe_stream_consumer(
          stream_arn: "arn:aws:kinesis:us-east-1:123456789012:stream/my-stream", # required
          consumer_name: "cosumerName", # required
          consumer_arn: "consumerArn", # required
        )
      end
      let(:responses) do
        {describe_stream_consumer: {
          consumer_description: {
            consumer_name: "John Doe",
            consumer_arn: "consumerArn",
            consumer_status: "CREATING",
            consumer_creation_timestamp: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
            stream_arn: "streamArn",
          },
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-stream" }
        let(:peer_service_source) { "streamname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("kinesis.describe_stream_consumer")
        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("describe_stream_consumer")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("kinesis")
        expect(span.get_tag("streamname")).to eq("my-stream")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("123456789012.control-kinesis.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("123456789012.control-kinesis.us-stubbed-1.amazonaws.com")
      end
    end
  end

  context "with an eventbridge client" do
    let(:client) { ::Aws::EventBridge::Client.new(stub_responses: responses) }

    describe "#put_rule" do
      subject!(:put_rule) do
        client.put_rule(
          {
            name: "RuleName", # required
            tags: [
              {
                key: "TagKey", # required
                value: "TagValue", # required
              },
            ],
          }
        )
      end

      let(:responses) do
        {put_rule: {
          rule_arn: "my-rule-arn",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "RuleName" }
        let(:peer_service_source) { "rulename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("eventbridge.put_rule")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("put_rule")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("eventbridge")
        expect(span.get_tag("rulename")).to eq("RuleName")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("events.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("events.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#list_targets_by_rule" do
      subject!(:list_targets_by_rule) do
        client.list_targets_by_rule(
          {
            rule: "RuleName", # required
          }
        )
      end

      let(:responses) do
        {list_targets_by_rule: {
          targets: [],
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "RuleName" }
        let(:peer_service_source) { "rulename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("eventbridge.list_targets_by_rule")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("list_targets_by_rule")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws_service")).to eq("eventbridge")
        expect(span.get_tag("rulename")).to eq("RuleName")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("events.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("events.us-stubbed-1.amazonaws.com")
      end
    end
  end

  context "with a stepfunction client" do
    let(:client) { ::Aws::States::Client.new(stub_responses: responses) }

    describe "#start_execution" do
      subject!(:start_execution) do
        client.start_execution(
          {
            state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine", # required
          }
        )
      end

      let(:responses) do
        {start_execution: {
          execution_arn: "execution-arn",
          start_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyStateMachine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.start_execution")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("start_execution")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("MyStateMachine")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#create_state_machine" do
      subject!(:create_state_machine) do
        client.create_state_machine(
          {
            name: "my-state-machine-name", # required
            definition: "Definition", # required
            role_arn: "Arn", # required
          }
        )
      end

      let(:responses) do
        {create_state_machine: {
          state_machine_arn: "arn",
          creation_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-state-machine-name" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.create_state_machine")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("create_state_machine")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("my-state-machine-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#describe_state_machine" do
      subject!(:describe_state_machine) do
        client.describe_state_machine(
          {
            state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:my-state-machine-name", # required
          }
        )
      end

      let(:responses) do
        {describe_state_machine: {
          state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:example-state-machine",
          name: "example-state-machine",
          status: "ACTIVE",
          definition: '{\'Comment\':\'An example state machine\',
                        \'StartAt\':\'HelloWorld\',
                        \'States\':{\'HelloWorld\':{\'Type\':\'Task\',
                        \'Resource\':\'arn:aws:lambda:us-east-1:123456789012:function:hello-world\',
                        \'End\':true}}}',
          role_arn: "arn:aws:iam::123456789012:role/StateExecutionRole",
          type: "STANDARD",
          creation_date: Time.now,
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-state-machine-name" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.describe_state_machine")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("describe_state_machine")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("my-state-machine-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#update_state_machine" do
      subject!(:update_state_machine) do
        client.update_state_machine(
          {
            state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:my-state-machine-name", # required
          }
        )
      end

      let(:responses) do
        {update_state_machine: {
          update_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-state-machine-name" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.update_state_machine")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("update_state_machine")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("my-state-machine-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#delete_state_machine" do
      subject!(:delete_state_machine) do
        client.delete_state_machine(
          {
            state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:my-state-machine-name", # required
          }
        )
      end

      let(:responses) do
        {delete_state_machine: {}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "my-state-machine-name" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.delete_state_machine")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("delete_state_machine")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("my-state-machine-name")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#describe_execution" do
      subject!(:describe_execution) do
        client.describe_execution(
          {
            execution_arn: "arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution",
          }
        )
      end

      let(:responses) do
        {describe_execution: {
          execution_arn: "string",
          state_machine_arn: "string",
          name: "string",
          status: "string",
          start_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
          stop_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
          input: "string",
          input_details: {
            included: true | false,
          },
          output: "string",
          output_details: {
            included: true | false,
          },
          trace_header: "string",
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "example-state-machine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.describe_execution")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("describe_execution")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("example-state-machine")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end

    describe "#stop_execution" do
      subject!(:stop_execution) do
        client.stop_execution(
          {
            execution_arn: "arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution",
          }
        )
      end

      let(:responses) do
        {stop_execution: {
          stop_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "example-state-machine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("states.stop_execution")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("stop_execution")
        expect(span.get_tag("aws_service")).to eq("states")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("statemachinename")).to eq("example-state-machine")
        expect(span.get_tag("path")).to eq("")
        expect(span.get_tag("host")).to eq("states.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("http.status_code")).to eq("200")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq("command")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME))
          .to eq("states.us-stubbed-1.amazonaws.com")
      end
    end
  end
end
