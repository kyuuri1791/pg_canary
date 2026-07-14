# frozen_string_literal: true

RSpec.describe PgCanary::Rules::JsonbSearchWithoutGin do
  it "detects @> on a jsonb column without a GIN index" do
    detections = detections_for { User.where("settings @> ?", '{"theme":"dark"}').to_a }

    expect(detections.map(&:rule_name)).to eq([:jsonb_search_without_gin])
    expect(detections.first.columns).to eq(["settings"])
    expect(detections.first.suggestion).to include("USING gin")
  end

  it "detects ->> extraction in WHERE without a matching expression index" do
    detections = detections_for { User.where("settings ->> 'theme' = ?", "dark").to_a }

    expect(detections.map(&:rule_name)).to eq([:jsonb_search_without_gin])
    expect(detections.first.message).to include("->>")
  end

  it "stays silent for @> when the column has a GIN index" do
    detections = detections_for { User.where("preferences @> ?", "{}").to_a }

    expect(detections).to be_empty
  end

  it "stays silent for ->> when a matching expression index exists" do
    detections = detections_for { User.where("metadata ->> 'plan' = ?", "pro").to_a }

    expect(detections).to be_empty
  end
end
