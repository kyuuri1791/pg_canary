# frozen_string_literal: true

RSpec.describe PgCanary::Rules::FunctionOnColumn do
  it "detects a function-wrapped column without a matching expression index" do
    detections = detections_for { User.where("lower(name) = ?", "taro").to_a }

    expect(detections.map(&:rule_name)).to eq([:function_on_column])
    detection = detections.first
    expect(detection.table).to eq("users")
    expect(detection.columns).to eq(["name"])
    expect(detection.suggestion).to include("((lower(name)))")
  end

  it "stays silent when a matching expression index exists" do
    detections = detections_for { User.where("lower(email) = ?", "taro@example.com").to_a }

    expect(detections).to be_empty
  end

  it "stays silent when the function is on the constant side" do
    detections = detections_for { User.where("email = lower('TARO@EXAMPLE.COM')").to_a }

    expect(detections).to be_empty
  end

  it "detects date() on a timestamp column" do
    detections = detections_for { Order.where("date(created_at) = ?", Date.new(2026, 1, 1)).to_a }

    expect(detections.map(&:rule_name)).to eq([:function_on_column])
    expect(detections.first.columns).to eq(["created_at"])
  end
end
