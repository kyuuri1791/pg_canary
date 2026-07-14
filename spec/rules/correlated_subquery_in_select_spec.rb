# frozen_string_literal: true

RSpec.describe PgCanary::Rules::CorrelatedSubqueryInSelect do
  it "detects a correlated scalar subquery in the SELECT list" do
    detections = detections_for do
      User.select("users.id, (SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id) AS cnt").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:correlated_subquery_in_select])
    expect(detections.first.table).to eq("users")
    expect(detections.first.suggestion).to include("JOIN")
  end

  it "stays silent for an uncorrelated scalar subquery" do
    detections = detections_for do
      User.select("users.id, (SELECT COUNT(*) FROM orders) AS cnt").to_a
    end

    expect(detections).to be_empty
  end
end
