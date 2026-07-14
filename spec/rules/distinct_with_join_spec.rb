# frozen_string_literal: true

RSpec.describe PgCanary::Rules::DistinctWithJoin do
  before { PgCanary.config.rules.distinct_with_join.enabled = true }

  it "detects DISTINCT combined with JOIN" do
    detections = detections_for do
      User.distinct.joins("JOIN orders ON orders.user_id = users.id").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:distinct_with_join])
    expect(detections.first.suggestion).to include("EXISTS")
  end

  it "stays silent for DISTINCT without JOIN" do
    detections = detections_for { User.distinct.to_a }

    expect(detections).to be_empty
  end

  it "stays silent for JOIN without DISTINCT" do
    detections = detections_for do
      User.joins("JOIN orders ON orders.user_id = users.id").to_a
    end

    expect(detections).to be_empty
  end
end
