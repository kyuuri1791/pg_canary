# frozen_string_literal: true

RSpec.describe PgCanary::Rules::HugeInList do
  it "detects an IN list above the threshold" do
    detections = detections_for { User.where(id: (1..501).to_a).to_a }

    expect(detections.map(&:rule_name)).to eq([:huge_in_list])
    expect(detections.first.message).to include("501 values")
    expect(detections.first.suggestion).to include("JOIN")
  end

  it "stays silent below the threshold" do
    detections = detections_for { User.where(id: (1..10).to_a).to_a }

    expect(detections).to be_empty
  end

  it "honours a custom threshold" do
    PgCanary.config.rules.huge_in_list.threshold = 5

    detections = detections_for { User.where(id: (1..6).to_a).to_a }

    expect(detections.map(&:rule_name)).to eq([:huge_in_list])
  end
end
