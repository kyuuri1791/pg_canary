# frozen_string_literal: true

RSpec.describe PgCanary::Rules::ArraySearchWithoutGin do
  it "detects @> on an array column without a GIN index" do
    detections = detections_for { User.where("tags @> ?", "{ruby}").to_a }

    expect(detections.map(&:rule_name)).to eq([:array_search_without_gin])
    expect(detections.first.columns).to eq(["tags"])
  end

  it "detects value = ANY(column)" do
    detections = detections_for { User.where("? = ANY(tags)", "ruby").to_a }

    expect(detections.map(&:rule_name)).to eq([:array_search_without_gin])
  end

  it "stays silent when the array column has a GIN index" do
    detections = detections_for { User.where("badges && ?", "{gold}").to_a }

    expect(detections).to be_empty
  end
end
