# frozen_string_literal: true

RSpec.describe PgCanary::Rules::UnindexedJoin do
  before { PgCanary.config.rules.unindexed_join.enabled = true }

  it "is disabled by default" do
    PgCanary.config.rules.unindexed_join.enabled = nil

    detections = detections_for do
      User.joins("JOIN prefectures ON prefectures.id = users.prefecture_id").to_a
    end

    expect(detections).to be_empty
  end

  it "detects a join condition on an unindexed column" do
    detections = detections_for do
      User.joins("JOIN prefectures ON prefectures.id = users.prefecture_id").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:unindexed_join])
    expect(detections.first.table).to eq("users")
    expect(detections.first.columns).to eq(["prefecture_id"])
  end

  it "stays silent when both join columns are indexed" do
    detections = detections_for do
      User.joins("JOIN orders ON orders.user_id = users.id").to_a
    end

    expect(detections).to be_empty
  end

  it "covers comma joins connected in WHERE" do
    detections = detections_for do
      User.from("users, prefectures").where("prefectures.id = users.prefecture_id").to_a
    end

    expect(detections.map(&:rule_name)).to eq([:unindexed_join])
  end
end
