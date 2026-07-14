# frozen_string_literal: true

RSpec.describe PgCanary::Rules::UnionInsteadOfUnionAll do
  before { PgCanary.config.rules.union_instead_of_union_all.enabled = true }

  it "detects UNION without ALL" do
    detections = detections_for do
      User.find_by_sql("SELECT id FROM users UNION SELECT user_id FROM orders")
    end

    expect(detections.map(&:rule_name)).to eq([:union_instead_of_union_all])
    expect(detections.first.suggestion).to include("UNION ALL")
  end

  it "stays silent for UNION ALL" do
    detections = detections_for do
      User.find_by_sql("SELECT id FROM users UNION ALL SELECT user_id FROM orders")
    end

    expect(detections).to be_empty
  end
end
