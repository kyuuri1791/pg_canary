# frozen_string_literal: true

RSpec.describe PgCanary::Rules::UnindexedWhere do
  before { PgCanary.config.rules.unindexed_where.enabled = true }

  it "is disabled by default" do
    PgCanary.config.rules.unindexed_where.enabled = nil

    detections = detections_for { User.where(name: "taro").to_a }

    expect(detections).to be_empty
  end

  it "detects an equality predicate on an unindexed column" do
    detections = detections_for { User.where(name: "taro").to_a }

    expect(detections.map(&:rule_name)).to eq([:unindexed_where])
    detection = detections.first
    expect(detection.table).to eq("users")
    expect(detection.columns).to eq(["name"])
    expect(detection.suggestion).to include("CREATE INDEX")
  end

  it "stays silent when the column is indexed" do
    detections = detections_for { User.where(email: "taro@example.com").to_a }

    expect(detections).to be_empty
  end

  it "stays silent on a primary-key lookup" do
    detections = detections_for { User.where(id: 1).to_a }

    expect(detections).to be_empty
  end

  it "honours leftmost-prefix matching on composite indexes" do
    silent = detections_for { Order.where(user_id: 1).to_a }
    noisy = detections_for { Order.where("created_at > ?", Time.now).to_a }

    expect(silent).to be_empty
    expect(noisy.map(&:rule_name)).to eq([:unindexed_where])
    expect(noisy.first.columns).to eq(["created_at"])
  end

  it "stays silent for column-to-column comparisons" do
    detections = detections_for { User.where("name = email").to_a }

    expect(detections).to be_empty
  end
end
