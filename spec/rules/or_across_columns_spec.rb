# frozen_string_literal: true

RSpec.describe PgCanary::Rules::OrAcrossColumns do
  before { PgCanary.config.rules.or_across_columns.enabled = true }

  it "detects OR spanning different columns" do
    detections = detections_for { User.where("name = ? OR email = ?", "a", "b").to_a }

    expect(detections.map(&:rule_name)).to eq([:or_across_columns])
    expect(detections.first.columns).to contain_exactly("name", "email")
  end

  it "stays silent for OR on the same column" do
    detections = detections_for { User.where("name = ? OR name = ?", "a", "b").to_a }

    expect(detections).to be_empty
  end
end
