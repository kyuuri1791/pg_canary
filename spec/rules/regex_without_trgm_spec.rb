# frozen_string_literal: true

RSpec.describe PgCanary::Rules::RegexWithoutTrgm do
  it "detects a regex match on a column without a trgm index" do
    detections = detections_for { User.where("name ~ ?", "taro").to_a }

    expect(detections.map(&:rule_name)).to eq([:regex_without_trgm])
    expect(detections.first.columns).to eq(["name"])
    expect(detections.first.suggestion).to include("gin_trgm_ops")
  end

  it "detects case-insensitive regex (~*) and SIMILAR TO" do
    regex = detections_for { User.where("name ~* ?", "taro").to_a }
    similar = detections_for { User.where("name SIMILAR TO ?", "%taro%").to_a }

    expect(regex.map(&:rule_name)).to eq([:regex_without_trgm])
    expect(similar.map(&:rule_name)).to eq([:regex_without_trgm])
    expect(similar.first.message).to include("SIMILAR TO")
  end

  it "stays silent when the column has a trgm index" do
    detections = detections_for { User.where("bio ~ ?", "taro").to_a }

    expect(detections).to be_empty
  end
end
