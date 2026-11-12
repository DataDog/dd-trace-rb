require "spec_helper"

require "datadog/tracing/contrib/utils/database"
require "datadog/tracing/contrib/aws/rds_endpoint"
require "datadog/tracing/span_operation"

RSpec.describe Datadog::Tracing::Contrib::Utils::Database do
  describe "#normalize_vendor" do
    subject(:result) { described_class.normalize_vendor(value) }

    context "when given" do
      context "nil" do
        let(:value) { nil }

        it { is_expected.to eq("defaultdb") }
      end

      context "sqlite3" do
        let(:value) { "sqlite3" }

        it { is_expected.to eq("sqlite") }
      end

      context "mysql2" do
        let(:value) { "mysql2" }

        it { is_expected.to eq("mysql2") }
      end

      context "postgresql" do
        let(:value) { "postgresql" }

        it { is_expected.to eq("postgres") }
      end

      context "customdb" do
        let(:value) { "customdb" }

        it { is_expected.to eq(value) }
      end
    end
  end

  describe ".set_rds_endpoint_tags" do
    subject(:set_rds_endpoint_tags) { described_class.set_rds_endpoint_tags(span, rds_endpoint) }

    let(:span) { Datadog::Tracing::SpanOperation.new("fake") }
    let(:rds_endpoint) { Datadog::Tracing::Contrib::Aws::RDSEndpoint.parse(hostname) }

    def rds_tags
      {
        identifier: span.get_tag("aws.rds.identifier"),
        endpoint_type: span.get_tag("aws.rds.endpoint_type"),
        region: span.get_tag("aws.region"),
        dbinstanceidentifier: span.get_tag("dbinstanceidentifier"),
        dbclusteridentifier: span.get_tag("dbclusteridentifier"),
      }
    end

    {
      "orders-db.cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" => {
        identifier: "orders-db",
        endpoint_type: "instance",
        region: "us-east-1",
        dbinstanceidentifier: "orders-db",
        dbclusteridentifier: nil,
      },
      "orders.cluster-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" => {
        identifier: "orders",
        endpoint_type: "cluster",
        region: "us-east-1",
        dbinstanceidentifier: nil,
        dbclusteridentifier: "orders",
      },
      "orders.cluster-ro-cdbfa1b2c3d4.eu-west-1.rds.amazonaws.com" => {
        identifier: "orders",
        endpoint_type: "cluster-ro",
        region: "eu-west-1",
        dbinstanceidentifier: nil,
        dbclusteridentifier: "orders",
      },
      "analytics.cluster-custom-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" => {
        identifier: "analytics",
        endpoint_type: "cluster-custom",
        region: "us-east-1",
        dbinstanceidentifier: nil,
        dbclusteridentifier: nil,
      },
      "orders-proxy.proxy-cdbfa1b2c3d4.us-east-1.rds.amazonaws.com" => {
        identifier: "orders-proxy",
        endpoint_type: "proxy",
        region: "us-east-1",
        dbinstanceidentifier: nil,
        dbclusteridentifier: nil,
      },
      "isoe-db.cdbfa1b2c3d4.eu-isoe-west-1.rds.cloud.adc-e.uk" => {
        identifier: "isoe-db",
        endpoint_type: "instance",
        region: "eu-isoe-west-1",
        dbinstanceidentifier: "isoe-db",
        dbclusteridentifier: nil,
      },
      "orders.cluster-cdbfa1b2c3d4.rds.cn-north-1.amazonaws.com.cn" => {
        identifier: "orders",
        endpoint_type: "cluster",
        region: "cn-north-1",
        dbinstanceidentifier: nil,
        dbclusteridentifier: "orders",
      },
    }.each do |host, expected|
      context "with #{host}" do
        let(:hostname) { host }

        it "sets the tags of that endpoint type" do
          set_rds_endpoint_tags

          expect(rds_tags).to eq(expected)
        end

        it "never sets the account label" do
          set_rds_endpoint_tags

          expect(span.tags.values).to all(satisfy { |value| !value.to_s.include?("cdbfa1b2c3d4") })
        end
      end
    end

    context "without an endpoint" do
      let(:rds_endpoint) { nil }

      it "sets no tags" do
        set_rds_endpoint_tags

        expect(span.tags).to be_empty
      end
    end
  end
end
