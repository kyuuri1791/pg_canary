# frozen_string_literal: true

RSpec.describe PgCanary::Rules::SelectStarWithHeavyColumns do
  before { PgCanary.config.rules.select_star_with_heavy_columns.enabled = true }

  it "detects SELECT * on a table with heavy columns" do
    detections = detections_for { User.where(id: 1).to_a }

    expect(detections.map(&:rule_name)).to eq([:select_star_with_heavy_columns])
    expect(detections.first.columns).to include("bio", "settings")
  end

  it "stays silent when columns are selected explicitly" do
    detections = detections_for { User.select(:id, :name).where(id: 1).to_a }

    expect(detections).to be_empty
  end

  it "stays silent for tables without heavy columns" do
    detections = detections_for { Prefecture.where(id: 1).to_a }

    expect(detections).to be_empty
  end

  it "honours a custom heavy-type list" do
    PgCanary.config.rules.select_star_with_heavy_columns.heavy_types = %w[bytea]

    detections = detections_for { User.where(id: 1).to_a }

    expect(detections).to be_empty
  end
end
