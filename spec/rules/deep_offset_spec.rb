# frozen_string_literal: true

RSpec.describe PgCanary::Rules::DeepOffset do
  it "detects a deep OFFSET from the runtime bind value" do
    detections = detections_for { User.offset(2000).limit(5).to_a }

    expect(detections.map(&:rule_name)).to eq([:deep_offset])
    expect(detections.first.message).to include("OFFSET 2000")
    expect(detections.first.suggestion).to include("keyset")
  end

  it "stays silent below the threshold" do
    detections = detections_for { User.offset(10).limit(5).to_a }

    expect(detections).to be_empty
  end

  it "honours a custom threshold" do
    PgCanary.config.rules.deep_offset.threshold = 100

    detections = detections_for { User.offset(200).limit(5).to_a }

    expect(detections.map(&:rule_name)).to eq([:deep_offset])
  end
end
