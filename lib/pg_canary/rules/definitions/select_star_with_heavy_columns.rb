# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # Tier 2 (opt-in): SELECT * (ActiveRecord's default) on a table that has
    # heavy columns (bytea / text / jsonb) transfers those payloads on every
    # query. Whether that matters depends on the data, hence opt-in.
    # Heavy types: config.rules.select_star_with_heavy_columns.heavy_types.
    class SelectStarWithHeavyColumns < Base
      def default_enabled
        false
      end

      def self.options
        { heavy_types: %w[bytea jsonb text].freeze }
      end

      def check(query)
        heavy_types = rule_config(query).heavy_types
        detections = []
        query.each_scope do |scope|
          star_tables(scope).each do |table|
            next unless applicable_table?(query, table)

            heavy = query.column_types(table).select { |_, type| heavy_types.include?(type) }.keys
            next if heavy.empty?

            detections << detection(
              query,
              table: table,
              columns: heavy,
              message: "SELECT * on #{table} transfers its heavy columns (#{heavy.join(", ")}) " \
                       "on every query.",
              suggestion: "Select only the columns you need (.select(:id, ...)), or move large " \
                          "payloads to a separate table loaded on demand."
            )
          end
        end
        detections
      end

      private

        # Tables whose rows are fetched with a star target (t.* or bare *).
        def star_tables(scope)
          tables = []
          scope.stmt.target_list.each do |target|
            res_target = target.unwrap
            next unless res_target.is_a?(PgQuery::ResTarget)

            column_ref = res_target.val&.unwrap
            next unless column_ref.is_a?(PgQuery::ColumnRef)

            fields = column_ref.fields.map(&:unwrap)
            next unless fields.last.is_a?(PgQuery::A_Star)

            qualifier = fields[-2]
            if qualifier.is_a?(PgQuery::String)
              table = scope.aliases[qualifier.sval]
              tables << table if table
            else
              tables.concat(scope.tables)
            end
          end
          tables.uniq
        end
    end
  end
end
