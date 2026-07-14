# frozen_string_literal: true

RSpec.describe PgCanary::Rules::NotInSubquery do
  it "detects NOT IN with a subquery" do
    detections = detections_for do
      User.where("id NOT IN (SELECT user_id FROM orders)").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:not_in_subquery])
    detection = detections.first
    expect(detection.table).to eq("users")
    expect(detection.suggestion).to include("NOT EXISTS")
  end

  it "detects AR's where.not(id: subquery)" do
    detections = detections_for do
      User.where.not(id: Order.select(:user_id)).to_a
    end

    expect(detections.map(&:rule_name)).to include(:not_in_subquery)
  end

  it "stays silent for NOT EXISTS" do
    detections = detections_for do
      User.where("NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id)").to_a
    end

    expect(detections).to be_empty
  end

  it "stays silent for NOT IN with a literal list" do
    detections = detections_for { User.where("id NOT IN (1, 2, 3)").to_a }

    expect(detections).to be_empty
  end
end
