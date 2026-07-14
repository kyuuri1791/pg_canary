# frozen_string_literal: true

RSpec.describe PgCanary::Rules::UnindexedOrderByWithLimit do
  before { PgCanary.config.rules.unindexed_order_by_with_limit.enabled = true }

  it "is disabled by default" do
    PgCanary.config.rules.unindexed_order_by_with_limit.enabled = nil

    detections = detections_for { User.order(:created_at).limit(5).to_a }

    expect(detections).to be_empty
  end

  it "detects ORDER BY + LIMIT on an unindexed sort key" do
    detections = detections_for { User.order(:created_at).limit(5).to_a }

    expect(detections.map(&:rule_name)).to eq([:unindexed_order_by_with_limit])
    expect(detections.first.columns).to eq(["created_at"])
  end

  it "stays silent when the sort key is indexed" do
    detections = detections_for { User.order(:email).limit(5).to_a }

    expect(detections).to be_empty
  end

  it "stays silent without a LIMIT" do
    detections = detections_for { User.order(:created_at).to_a }

    expect(detections).to be_empty
  end

  it "stays silent for .first on the primary key" do
    detections = detections_for { User.order(:id).first }

    expect(detections).to be_empty
  end
end
