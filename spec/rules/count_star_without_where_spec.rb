# frozen_string_literal: true

RSpec.describe PgCanary::Rules::CountStarWithoutWhere do
  before { PgCanary.config.rules.count_star_without_where.enabled = true }

  it "detects COUNT(*) without WHERE" do
    detections = detections_for { User.count }

    expect(detections.map(&:rule_name)).to eq([:count_star_without_where])
    expect(detections.first.suggestion).to include("reltuples")
  end

  it "stays silent when a WHERE clause is present" do
    detections = detections_for { User.where(email: "a@b.c").count }

    expect(detections).to be_empty
  end
end
