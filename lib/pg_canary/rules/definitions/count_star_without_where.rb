# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # SELECT COUNT(*) without WHERE. Because of MVCC,
    # PostgreSQL has no O(1) row count — this scans the whole table.
    class CountStarWithoutWhere < Base
      default_enabled false

      def check
        detections = []
        each_scope do |scope|
          stmt = scope.stmt
          next if stmt.where_clause || stmt.group_clause.any?
          next unless count_star?(stmt)

          tables = scope.tables
          next unless tables.length == 1

          table = tables.first
          next unless applicable_table?(table)

          detections << detection(
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
            res_target = target.unwrap
            next false unless res_target.is_a?(PgQuery::ResTarget)

            func = res_target.val&.unwrap
            func.is_a?(PgQuery::FuncCall) && func.agg_star && func.function_name == "count"
          end
        end
    end
  end
end
