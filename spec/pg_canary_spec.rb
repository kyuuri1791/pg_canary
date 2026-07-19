# frozen_string_literal: true

RSpec.describe PgCanary do
  it "has a version number" do
    expect(PgCanary::VERSION).not_to be nil
  end

  it "runs all built-in rules" do
    expect(PgCanary::Rules::Base.all.map(&:rule_name)).to contain_exactly(
      # Tier 1
      :leading_wildcard_like, :regex_without_trgm, :function_on_column,
      :order_by_random, :not_in_subquery, :implicit_cast, :cartesian_join,
      :correlated_subquery_in_select, :jsonb_search_without_gin,
      :array_search_without_gin, :deep_offset, :huge_in_list,
      # Tier 2
      :unindexed_where, :unindexed_order_by_with_limit, :unindexed_join,
      :count_star_without_where, :distinct_with_join,
      :union_instead_of_union_all, :or_across_columns,
      :select_star_with_heavy_columns, :query_complexity
    )
  end

  it "maps every rule file to a rule in Rules::Base.all" do
    files = Dir[File.join(__dir__, "../lib/pg_canary/rules/definitions/*.rb")]
            .map { |f| File.basename(f, ".rb") }

    expect(PgCanary::Rules::Base.all.map { |klass| klass.rule_name.to_s }).to match_array(files)
  end

  it "raises on unknown rule names in config (typo protection)" do
    expect { PgCanary.config.rules.unindexd_where }.to raise_error(NoMethodError)
  end

  it "raises on unknown rule options" do
    expect { PgCanary.config.rules.order_by_random.threshold = 1 }.to raise_error(NoMethodError)
  end

  it "ignores INSERT / UPDATE / DELETE" do
    detections = detections_for do
      user = User.create!(name: "%taro%")
      user.update!(name: "x")
      user.destroy!
    end

    expect(detections).to be_empty
  end
end
