# frozen_string_literal: true

RSpec.describe PgCanary::Rules::ImplicitCast do
  it "detects an integer column compared with a numeric literal" do
    detections = detections_for { User.where("age = 1.5").to_a }

    expect(detections.map(&:rule_name)).to eq([:implicit_cast])
    detection = detections.first
    expect(detection.table).to eq("users")
    expect(detection.columns).to eq(["age"])
    expect(detection.message).to include("integer")
  end

  it "detects the literal on the left-hand side too" do
    detections = detections_for { User.where("1.5 > age").to_a }

    expect(detections.map(&:rule_name)).to eq([:implicit_cast])
  end

  it "stays silent for an integer literal" do
    detections = detections_for { User.where("age = 30").to_a }

    expect(detections).to be_empty
  end

  it "stays silent when the column is numeric" do
    detections = detections_for { User.where("score = 1.5").to_a }

    expect(detections).to be_empty
  end
end
