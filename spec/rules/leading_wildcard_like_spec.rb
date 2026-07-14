# frozen_string_literal: true

RSpec.describe PgCanary::Rules::LeadingWildcardLike do
  it "detects a leading-wildcard LIKE on a column without a trgm index" do
    detections = detections_for { User.where("name LIKE ?", "%taro%").to_a }

    expect(detections.map(&:rule_name)).to eq([:leading_wildcard_like])
    detection = detections.first
    expect(detection.table).to eq("users")
    expect(detection.columns).to eq(["name"])
    expect(detection.suggestion).to include("gin_trgm_ops")
    expect(detection.location).to include("leading_wildcard_like_spec.rb")
  end

  it "detects ILIKE with a leading wildcard" do
    detections = detections_for { User.where("name ILIKE ?", "%taro").to_a }

    expect(detections.map(&:rule_name)).to eq([:leading_wildcard_like])
  end

  it "resolves bind parameters ($1) from the event binds" do
    binds = [ActiveRecord::Relation::QueryAttribute.new("name", "%taro%", ActiveModel::Type::String.new)]
    detections = detections_for do
      ActiveRecord::Base.connection.exec_query(
        'SELECT * FROM "users" WHERE "users"."name" LIKE $1', "User Load", binds
      )
    end

    expect(detections.map(&:rule_name)).to eq([:leading_wildcard_like])
  end

  it "stays silent when the column has a pg_trgm GIN index" do
    detections = detections_for { User.where("bio LIKE ?", "%taro%").to_a }

    expect(detections).to be_empty
  end

  it "stays silent for a trailing wildcard" do
    detections = detections_for { User.where("name LIKE ?", "taro%").to_a }

    expect(detections).to be_empty
  end

  it "stays silent for tables in ignore_tables" do
    PgCanary.config.ignore_tables << "users"
    detections = detections_for { User.where("name LIKE ?", "%taro%").to_a }

    expect(detections).to be_empty
  end

  it "honours a severity override" do
    PgCanary.config.rules.leading_wildcard_like.severity = :error
    detections = detections_for { User.where("name LIKE ?", "%taro%").to_a }

    expect(detections.first.severity).to eq(:error)
  end

  it "can be disabled" do
    PgCanary.config.rules.leading_wildcard_like.enabled = false
    detections = detections_for { User.where("name LIKE ?", "%taro%").to_a }

    expect(detections).to be_empty
  end
end
