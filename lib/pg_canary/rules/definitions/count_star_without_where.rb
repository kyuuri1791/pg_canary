# frozen_string_literal: true

module PgCanary
  module Rules
    # Tier 2 (opt-in): SELECT COUNT(*) without WHERE. Because of MVCC,
    # PostgreSQL has no O(1) row count — this scans the whole table.
    class CountStarWithoutWhere < Base
      def default_enabled
        false
      end

      def check(query)
        detections = []
        query.each_scope do |scope|
          stmt = scope.stmt
          next if stmt.where_clause || stmt.group_clause.any?
          next unless count_star?(stmt)

          tables = scope.tables
          next unless tables.length == 1

          table = tables.first
          next unless applicable_table?(query, table)

          detections << detection(
            query,
            table: table,
            message: "COUNT(*) without WHERE scans the whole #{table} table — PostgreSQL's MVCC " \
                     "has no O(1) row count.",
            suggestion: <<~SUGGESTION.chomp
              If an approximation is acceptable, use the planner's estimate:
                SELECT reltuples::bigint FROM pg_class WHERE relname = '#{table}';
              For exact counts displayed frequently, maintain a counter cache.
            SUGGESTION
          )
        end
        detections
      end

      private

      def count_star?(stmt)
        stmt.target_list.any? do |target|
          res_target = unwrap_node(target)
          next false unless res_target.is_a?(PgQuery::ResTarget)

          func = unwrap_node(res_target.val)
          func.is_a?(PgQuery::FuncCall) && func.agg_star && function_name(func) == "count"
        end
      end
    end
  end
end
