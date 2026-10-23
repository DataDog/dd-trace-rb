require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/analytics_examples"
require "datadog/tracing/contrib/integration_examples"
require "datadog/tracing/contrib/environment_service_name_examples"
require "datadog/tracing/contrib/span_attribute_schema_examples"
require "datadog/tracing/contrib/peer_service_configuration_examples"
require "datadog/tracing/contrib/svc_src_examples"

require "aws-sdk"

require "datadog/tracing"
require "datadog/tracing/metadata/ext"
require "datadog"
require "datadog/tracing/contrib/aws/patcher"

RSpec.describe "AWS instrumentation" do
  let(:configuration_options) { {} }
  let(:server_error_statuses) { nil }

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

  context "with a dynamodb client addressing a table by ARN" do
    let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses) }

    describe "#get_item" do
      subject!(:get_item) do
        client.get_item(
          table_name: "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable",
          key: {id: "1234"}
        )
      end

      let(:responses) do
        {get_item: {item: {"AlbumTitle" => "Songs About Life"}}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyTable" }
        let(:peer_service_source) { "tablename" }
      end

      it "resolves the table name and account out of the ARN" do
        expect(span.resource).to eq("dynamodb.get_item")
        expect(span.get_tag("tablename")).to eq("MyTable")
        expect(span.get_tag("aws.table.name")).to eq("MyTable")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end

      it "reports the ARN exactly as the request supplied it" do
        expect(span.get_tag("aws.table.arn"))
          .to eq("arn:aws:dynamodb:us-east-1:123456789012:table/MyTable")
      end
    end
  end

  context "with a dynamodb client addressing a table in another Region and account" do
    # The client is pinned to a Region the target ARN does not name, which is
    # what a cross-Region, cross-account table request looks like.
    let(:client) do
      ::Aws::DynamoDB::Client.new(
        stub_responses: responses,
        region: "us-west-2",
        credentials: ::Aws::Credentials.new("stubbed-key", "stubbed-secret")
      )
    end

    describe "#get_item" do
      subject!(:get_item) do
        client.get_item(
          table_name: "arn:aws:dynamodb:eu-central-1:999999999999:table/CrossRegionTable",
          key: {id: "1234"}
        )
      end

      let(:responses) do
        {get_item: {item: {"AlbumTitle" => "Songs About Life"}}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "CrossRegionTable" }
        let(:peer_service_source) { "tablename" }
      end

      it "resolves the target's name and owning account" do
        expect(span.get_tag("tablename")).to eq("CrossRegionTable")
        expect(span.get_tag("aws.table.name")).to eq("CrossRegionTable")
        expect(span.get_tag("aws_account")).to eq("999999999999")
      end

      it "keeps aws.region on the request endpoint's Region" do
        expect(span.get_tag("aws.region")).to eq("us-west-2")
        expect(span.get_tag("region")).to eq("us-west-2")
        expect(span.get_tag("host")).to eq("dynamodb.us-west-2.amazonaws.com")
      end

      # The target Region is not dropped and does not need a tag of its own:
      # the complete ARN carries it.
      it "retains the target Region inside the complete ARN" do
        expect(span.get_tag("aws.table.arn"))
          .to eq("arn:aws:dynamodb:eu-central-1:999999999999:table/CrossRegionTable")
      end
    end
  end

  context "with a dynamodb client given a global table ARN" do
    let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses) }

    describe "#get_item" do
      subject!(:get_item) do
        client.get_item(
          table_name: "arn:aws:dynamodb::123456789012:global-table/MyTable",
          key: {id: "1234"}
        )
      end

      let(:responses) do
        {get_item: {item: {"AlbumTitle" => "Songs About Life"}}}
      end

      # `TableName` does not accept a global table ARN, so resolving one would
      # claim identity for a request the API would have rejected.
      it "keeps the value in the legacy tag and claims no identity" do
        expect(span.get_tag("tablename")).to eq("arn:aws:dynamodb::123456789012:global-table/MyTable")
        expect(span.get_tag("aws.table.name")).to be_nil
        expect(span.get_tag("aws.table.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end
  end

  context "with a dynamodb client given a table stream ARN" do
    let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses) }
    let(:stream_arn) { "arn:aws:dynamodb:us-east-1:123456789012:table/MyTable/stream/2024-01-01T00:00:00.000" }

    describe "#get_item" do
      subject!(:get_item) { client.get_item(table_name: stream_arn, key: {id: "1234"}) }

      let(:responses) do
        {get_item: {item: {"AlbumTitle" => "Songs About Life"}}}
      end

      # A stream ARN extends the `table/<name>` resource with further
      # segments, so it is not a value `TableName` accepts and must not be
      # resolved to the table it belongs to.
      it "keeps the value in the legacy tag and claims no identity" do
        expect(span.get_tag("tablename")).to eq(stream_arn)
        expect(span.get_tag("aws.table.name")).to be_nil
        expect(span.get_tag("aws.table.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end
  end

  context "with a dynamodb client given an empty table name" do
    let(:client) { ::Aws::DynamoDB::Client.new(stub_responses: responses) }

    describe "#get_item" do
      subject!(:get_item) { client.get_item(table_name: "", key: {id: "1234"}) }

      let(:responses) do
        {get_item: {item: {"AlbumTitle" => "Songs About Life"}}}
      end

      # The legacy tag keeps its pre-existing unconditional write, which
      # `peer.service` resolution depends on. `aws.table.name` is new, and an
      # empty one would publish a target identity the request never named.
      it "writes the legacy tag but not the new one" do
        expect(span.get_tag("tablename")).to eq("")
        expect(span.get_tag("aws.table.name")).to be_nil
      end
    end
  end

  context "with a kinesis client given a stream ARN and a conflicting stream name" do
    let(:client) { ::Aws::Kinesis::Client.new(stub_responses: responses) }

    describe "#put_record" do
      subject!(:put_record) do
        client.put_record(
          stream_arn: "arn:aws:kinesis:us-east-1:123456789012:stream/arn-stream",
          stream_name: "param-stream",
          partition_key: "partition-1",
          data: "Hello world!"
        )
      end

      let(:responses) do
        {put_record: {shard_id: "1234", sequence_number: "5678", encryption_type: "NONE"}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "arn-stream" }
        let(:peer_service_source) { "streamname" }
      end

      it "prefers the ARN and reports it alongside the account" do
        expect(span.resource).to eq("kinesis.put_record")
        expect(span.get_tag("streamname")).to eq("arn-stream")
        expect(span.get_tag("aws.stream.name")).to eq("arn-stream")
        expect(span.get_tag("aws.stream.arn"))
          .to eq("arn:aws:kinesis:us-east-1:123456789012:stream/arn-stream")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end
    end
  end

  context "with an SNS client publishing to a mobile platform endpoint" do
    let(:client) { ::Aws::SNS::Client.new(stub_responses: responses) }

    describe "#publish" do
      subject!(:publish) do
        client.publish(
          target_arn: "arn:aws:sns:us-west-2:123456789012:endpoint/APNS/my-app/1234-5678",
          message: "Hello, world!"
        )
      end

      let(:responses) do
        {publish: {message_id: "1234"}}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "sns.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it "does not label the endpoint as a topic" do
        expect(span.resource).to eq("sns.publish")
        # The legacy tag is always written, so an unresolved topic leaves it
        # empty rather than absent.
        expect(span.get_tag("topicname")).to eq("")
        expect(span.get_tag("aws.topic.name")).to be_nil
        expect(span.get_tag("aws.topic.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end
  end

  context "with a states client" do
    let(:client) { ::Aws::States::Client.new(stub_responses: responses) }

    describe "#describe_execution" do
      subject!(:describe_execution) do
        client.describe_execution(
          execution_arn: "arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution"
        )
      end

      let(:responses) do
        {describe_execution: {
          execution_arn: "arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution",
          state_machine_arn: "arn:aws:states:us-east-1:999999999999:stateMachine:ResponseStateMachine",
          status: "RUNNING",
          start_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "example-state-machine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "reports the execution ARN and the state machine it belongs to" do
        expect(span.resource).to eq("states.describe_execution")
        expect(span.get_tag("statemachinename")).to eq("example-state-machine")
        expect(span.get_tag("aws.execution.arn"))
          .to eq("arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end

      it "reads the request, not the response" do
        # The response carries a state machine ARN in another account; only the
        # request's own parameters describe what this span called.
        expect(span.get_tag("aws.state_machine.arn")).to be_nil
        expect(span.get_tag("aws_account")).not_to eq("999999999999")
      end
    end

    describe "#describe_state_machine" do
      subject!(:describe_state_machine) do
        client.describe_state_machine(
          state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine"
        )
      end

      let(:responses) do
        {describe_state_machine: {
          state_machine_arn: "state-machine-arn",
          name: "MyStateMachine",
          definition: "Definition",
          role_arn: "role-arn",
          type: "STANDARD",
          creation_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "schema version span"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyStateMachine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "reports the state machine ARN" do
        expect(span.resource).to eq("states.describe_state_machine")
        expect(span.get_tag("statemachinename")).to eq("MyStateMachine")
        expect(span.get_tag("aws.state_machine.arn"))
          .to eq("arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine")
        expect(span.get_tag("aws.execution.arn")).to be_nil
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end
    end

    describe "#start_execution with consistent ARNs" do
      subject!(:start_execution) do
        client.start_execution(
          state_machine_arn: "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine",
          name: "my-execution"
        )
      end

      let(:responses) do
        {start_execution: {
          execution_arn: "arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:my-execution",
          start_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "MyStateMachine" }
        let(:peer_service_source) { "statemachinename" }
      end

      it "prefers the state machine ARN over the request's execution name" do
        expect(span.get_tag("statemachinename")).to eq("MyStateMachine")
        expect(span.get_tag("aws.state_machine.arn"))
          .to eq("arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end
    end

    # `name` on `StartExecution` is the EXECUTION's name. It used to be
    # reported as `statemachinename` -- and therefore as `peer.service` --
    # whenever the ARN beside it could not be resolved. Nothing is reported
    # now, so `peer.service` falls back to the hostname instead of naming the
    # dependency after one execution.
    describe "#start_execution with a malformed state machine ARN" do
      subject!(:start_execution) do
        client.start_execution(
          state_machine_arn: "arn:aws:states:us-east-1:oops:stateMachine:MyStateMachine",
          name: "my-execution"
        )
      end

      let(:responses) do
        {start_execution: {
          execution_arn: "arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:my-execution",
          start_date: Time.new(2023, 3, 31, 12, 30, 0, "-04:00"),
        }}
      end

      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "states.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it "does not report the execution name as the state machine" do
        expect(span.resource).to eq("states.start_execution")
        expect(span.get_tag("statemachinename")).to be_nil
        expect(span.get_tag("aws.state_machine.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end
  end

  context "with the Step Functions API model" do
    # No Step Functions operation accepts `stateMachineArn` and `executionArn`
    # in the same request, so a conflicting pair cannot be built through the
    # SDK's own operations. The handler's conflict handling is a guard against
    # a params hash that carries both, and is covered at the handler level in
    # `service/states_spec.rb`. This assertion pins that assumption, so an
    # operation that does carry both surfaces here instead of silently making
    # the guard reachable in production untested.
    it "has no operation that supplies both ARNs" do
      carrying_both = []
      ::Aws::States::Client.api.operations.each do |name, operation|
        members = operation.input.shape.member_names
        carrying_both << name if members.include?(:state_machine_arn) && members.include?(:execution_arn)
      end

      expect(carrying_both).to be_empty
    end
  end

  context "with a lambda client" do
    let(:client) { ::Aws::Lambda::Client.new(stub_responses: responses) }

    let(:responses) do
      {invoke: {status_code: 200, payload: "{}"}}
    end

    describe "#invoke with a bare function name" do
      subject!(:invoke) { client.invoke(function_name: "my-function") }

      it_behaves_like "schema version span"
      it_behaves_like "environment service name", "DD_TRACE_AWS_SERVICE_NAME"
      it_behaves_like "configured peer service span", "DD_TRACE_AWS_PEER_SERVICE"
      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "lambda.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end

      it "generates a span" do
        expect(span.name).to eq("aws.command")
        expect(span.service).to eq("aws")
        expect(span.type).to eq("http")
        expect(span.resource).to eq("lambda.invoke")

        expect(span.get_tag("aws.agent")).to eq("aws-sdk-ruby")
        expect(span.get_tag("aws.operation")).to eq("invoke")
        expect(span.get_tag("aws_service")).to eq("lambda")
        expect(span.get_tag("region")).to eq("us-stubbed-1")
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("host")).to eq("lambda.us-stubbed-1.amazonaws.com")
        expect(span.get_tag("http.method")).to eq("POST")
        expect(span.get_tag("span.kind")).to eq("client")

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("aws")
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq("command")
      end

      it "reports no ARN and no account, because the request carries none" do
        expect(span.get_tag("aws.function.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end

    describe "#invoke with a qualified function name" do
      subject!(:invoke) { client.invoke(function_name: "my-function:PROD") }

      it "reports the function rather than the alias" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws.function.arn")).to be_nil
      end
    end

    describe "#invoke with a full ARN" do
      subject!(:invoke) do
        client.invoke(function_name: "arn:aws:lambda:us-west-2:123456789012:function:my-function")
      end

      it "reports the function name, ARN and account" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws.function.arn"))
          .to eq("arn:aws:lambda:us-west-2:123456789012:function:my-function")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end

      it_behaves_like "a peer service span" do
        let(:peer_service_val) { "lambda.us-stubbed-1.amazonaws.com" }
        let(:peer_service_source) { "peer.hostname" }
      end
    end

    describe "#invoke with a qualified full ARN" do
      subject!(:invoke) do
        client.invoke(
          function_name: "arn:aws:lambda:us-west-2:123456789012:function:my-function:PROD"
        )
      end

      it "reports the name without its qualifier and the ARN exactly as requested" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws.function.arn"))
          .to eq("arn:aws:lambda:us-west-2:123456789012:function:my-function:PROD")
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end
    end

    describe "#invoke with a partial ARN" do
      subject!(:invoke) { client.invoke(function_name: "123456789012:function:my-function") }

      it "reports the function name and account but no ARN" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("aws.function.arn")).to be_nil
      end
    end

    describe "#invoke with a malformed partial ARN" do
      subject!(:invoke) { client.invoke(function_name: "123456789012:function:") }

      # An account with no function to attach it to is worse than no identity
      # at all, so a partial ARN that does not fully validate yields nothing.
      it "reports neither a name nor an account" do
        expect(span.get_tag("aws.function.name")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
        expect(span.get_tag("aws.function.arn")).to be_nil
      end

      it "still generates the span" do
        expect(span.resource).to eq("lambda.invoke")
        expect(span.get_tag("aws_service")).to eq("lambda")
      end
    end

    describe "#invoke with a layer ARN" do
      subject!(:invoke) do
        client.invoke(function_name: "arn:aws:lambda:us-west-2:123456789012:layer:my-layer:1")
      end

      it "claims no function identity" do
        expect(span.get_tag("aws.function.name")).to be_nil
        expect(span.get_tag("aws.function.arn")).to be_nil
        expect(span.get_tag("aws_account")).to be_nil
      end
    end

    describe "#invoke with a dotted function name" do
      subject!(:invoke) { client.invoke(function_name: "my.function.v2") }

      it "resolves the whole dotted name" do
        expect(span.get_tag("aws.function.name")).to eq("my.function.v2")
        expect(span.get_tag("aws.function.arn")).to be_nil
      end
    end

    describe "#invoke with a $LATEST.PUBLISHED qualifier" do
      let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my-function:$LATEST.PUBLISHED" }

      subject!(:invoke) { client.invoke(function_name: function_name) }

      it "keeps the qualifier in the ARN and out of the name" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws.function.arn")).to eq(function_name)
        expect(span.get_tag("aws_account")).to eq("123456789012")
      end
    end

    describe "#invoke with a Region-prefixed partial ARN" do
      subject!(:invoke) { client.invoke(function_name: "us-west-2:123456789012:function:my-function") }

      it "reports the function name and account but no ARN" do
        expect(span.get_tag("aws.function.name")).to eq("my-function")
        expect(span.get_tag("aws_account")).to eq("123456789012")
        expect(span.get_tag("aws.function.arn")).to be_nil
      end
    end

    # Each value below used to be reported as a function called
    # `123456789012`, because the handler read the first colon-delimited
    # segment of anything it could not parse.
    describe "#invoke with a value that cannot name a function" do
      [
        ["only an account number", "123456789012"],
        ["a layer in place of the function", "123456789012:layer:my-layer:1"],
        ["a wrong-sized account", "12345:function:my-function"],
        ["a segment beyond the qualifier", "arn:aws:lambda:us-west-2:123456789012:function:my-fn:PROD:extra"],
      ].each do |description, value|
        context "with #{description}" do
          subject!(:invoke) { client.invoke(function_name: value) }

          it "claims no function identity and no account" do
            expect(span.get_tag("aws.function.name")).to be_nil
            expect(span.get_tag("aws.function.arn")).to be_nil
            expect(span.get_tag("aws_account")).to be_nil
          end

          it "still generates the span" do
            expect(span.resource).to eq("lambda.invoke")
            expect(span.get_tag("aws_service")).to eq("lambda")
          end
        end
      end
    end

    # Lambda `peer.service` comes from `peer.hostname` on every form a
    # `FunctionName` can take. This is the cross-tracer compatible behavior
    # the other Datadog tracers implement, so it is asserted for each form
    # rather than only for the bare name.
    describe "peer.service across every FunctionName form" do
      [
        ["a bare name", "my-function"],
        ["a qualified name", "my-function:PROD"],
        ["a dotted name", "my.function.v2"],
        ["a name qualified by $LATEST.PUBLISHED", "my-function:$LATEST.PUBLISHED"],
        ["a partial ARN", "123456789012:function:my-function"],
        ["a Region-prefixed partial ARN", "us-west-2:123456789012:function:my-function"],
        ["a full ARN", "arn:aws:lambda:us-west-2:123456789012:function:my-function"],
        ["a qualified full ARN", "arn:aws:lambda:us-west-2:123456789012:function:my-function:PROD"],
        ["a malformed partial ARN", "123456789012:function:"],
        ["a value that is only an account number", "123456789012"],
      ].each do |description, value|
        context "with #{description}" do
          subject!(:invoke) { client.invoke(function_name: value) }

          it_behaves_like "a peer service span" do
            let(:peer_service_val) { "lambda.us-stubbed-1.amazonaws.com" }
            let(:peer_service_source) { "peer.hostname" }
          end
        end
      end
    end
  end
end
