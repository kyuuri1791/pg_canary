# frozen_string_literal: true

RSpec.describe PgCanary::Rules::CartesianJoin do
  it "detects an explicit CROSS JOIN between tables" do
    detections = detections_for { User.joins("CROSS JOIN orders").to_a }

    expect(detections.map(&:rule_name)).to eq([:cartesian_join])
    expect(detections.first.message).to include("cross product")
  end

  it "detects a comma join with no connecting WHERE condition" do
    detections = detections_for { User.from("users, orders").to_a }

    expect(detections.map(&:rule_name)).to eq([:cartesian_join])
  end

  it "stays silent for a comma join connected in WHERE" do
    detections = detections_for do
      User.from("users, orders").where("orders.user_id = users.id").to_a
    end

    expect(detections).to be_empty
  end

  it "stays silent for JOIN ... ON" do
    detections = detections_for do
      User.joins("JOIN orders ON orders.user_id = users.id").to_a
    end

    expect(detections).to be_empty
  end
end
