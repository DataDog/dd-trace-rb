require "datadog/tracing/contrib/support/spec_helper"

require "datadog"
require "datadog/tracing/contrib/pg/instrumentation"

RSpec.describe Datadog::Tracing::Contrib::Pg::Instrumentation do
  let(:connection_class) do
    Class.new do
      attr_reader :host, :port, :db, :user

      def initialize(host:, port: 5432, db: "orders", user: "postgres")
        @host = host
        @port = port
        @db = db
        @user = user
      end

      def exec(_sql, *_args)
        nil
      end

      include Datadog::Tracing::Contrib::Pg::Instrumentation
    end
  end

  let(:connection) { connection_class.new(host: host) }

  before { connection.exec("SELECT 1") }

  context "with an RDS instance endpoint" do
    let(:host) { "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "tags the RDS identity alongside the existing host tags" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to eq("orders-db")
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("instance")
      expect(span.get_tag("aws.region")).to eq("us-east-1")
      expect(span.get_tag("dbinstanceidentifier")).to eq("orders-db")
      expect(span.get_tag("dbclusteridentifier")).to be_nil
    end
  end

  context "with an Aurora custom endpoint" do
    let(:host) { "analytics.cluster-custom-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "tags the endpoint name without naming a cluster or an instance" do
      expect(span.get_tag("aws.rds.identifier")).to eq("analytics")
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("cluster-custom")
      expect(span.get_tag("dbclusteridentifier")).to be_nil
      expect(span.get_tag("dbinstanceidentifier")).to be_nil
    end
  end

  context "with an RDS Proxy endpoint" do
    let(:host) { "orders-proxy.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "tags the proxy name without naming the target it routes to" do
      expect(span.get_tag("aws.rds.identifier")).to eq("orders-proxy")
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("proxy")
      expect(span.get_tag("dbclusteridentifier")).to be_nil
      expect(span.get_tag("dbinstanceidentifier")).to be_nil
    end
  end

  context "with an endpoint outside the commercial partition" do
    let(:host) { "orders-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk" }

    it "tags the RDS identity the same way as in any other partition" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to eq("orders-db")
      expect(span.get_tag("aws.rds.endpoint_type")).to eq("instance")
      expect(span.get_tag("aws.region")).to eq("eu-isoe-west-1")
      expect(span.get_tag("dbinstanceidentifier")).to eq("orders-db")
    end
  end

  context "with a Region its DNS suffix does not serve" do
    let(:host) { "orders-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.amazonaws.com" }

    it "leaves the span unchanged, because that endpoint does not exist" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end

  context "with an RDS Proxy custom endpoint, which is deliberately not read" do
    let(:host) { "readonly.endpoint.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" }

    it "leaves the span unchanged rather than guessing at the identity" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end

  context "with a non-RDS host" do
    let(:host) { "postgres.internal.example.com" }

    it "leaves the span unchanged" do
      expect(span.get_tag("out.host")).to eq(host)
      expect(span.get_tag("aws.rds.identifier")).to be_nil
      expect(span.get_tag("aws.rds.endpoint_type")).to be_nil
      expect(span.get_tag("aws.region")).to be_nil
    end
  end
end
