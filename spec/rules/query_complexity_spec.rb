# frozen_string_literal: true

RSpec.describe PgCanary::Rules::QueryComplexity do
  before { PgCanary.config.rules.query_complexity.enabled = true }

  it "detects too many joins (custom threshold)" do
    PgCanary.config.rules.query_complexity.max_joins = 2

    detections = detections_for do
      User.joins(<<~SQL).to_a
        JOIN orders o1 ON o1.user_id = users.id
        JOIN orders o2 ON o2.user_id = users.id
        JOIN orders o3 ON o3.user_id = users.id
      SQL
    end

    expect(detections.map(&:rule_name)).to eq([:query_complexity])
    expect(detections.first.message).to include("3 joins")
  end

  it "detects deep subquery nesting (custom threshold)" do
    PgCanary.config.rules.query_complexity.max_depth = 2

    detections = detections_for do
      User.where("id IN (SELECT user_id FROM orders WHERE user_id IN (SELECT id FROM users))").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:query_complexity])
    expect(detections.first.message).to include("depth 3")
  end

  it "stays silent for ordinary queries at default thresholds" do
    detections = detections_for do
      User.joins("JOIN orders ON orders.user_id = users.id").where(email: "a@b.c").to_a
    end

    expect(detections).to be_empty
  end
end
