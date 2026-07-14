# frozen_string_literal: true

RSpec.describe PgCanary::Rules::OrderByRandom do
  it "detects ORDER BY RANDOM()" do
    detections = detections_for { User.order(Arel.sql("RANDOM()")).first }

    expect(detections.map(&:rule_name)).to eq([:order_by_random])
    expect(detections.first.table).to eq("users")
    expect(detections.first.message).to include("RANDOM()")
  end

  it "detects lowercase random()" do
    detections = detections_for { User.order(Arel.sql("random()")).limit(3).to_a }

    expect(detections.map(&:rule_name)).to eq([:order_by_random])
  end

  it "stays silent for a plain column sort" do
    detections = detections_for { User.order(:name).to_a }

    expect(detections).to be_empty
  end
end
