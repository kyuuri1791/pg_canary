# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # ORDER BY RANDOM() sorts the entire result set just to pick rows —
    # always suspicious regardless of table size.
    class OrderByRandom < Base
      default_enabled true

      def check(query)
        detections = []
        query.each_scope do |scope|
          scope.sort_items.each do |sort_by|
            func = sort_by.node&.unwrap
            next unless func.is_a?(PgQuery::FuncCall)
            next unless func.function_name == "random"

            detections << detection(
              query,
              table: scope.tables.length == 1 ? scope.tables.first : nil,
              message: "ORDER BY RANDOM() reads and sorts every row, so it gets slower " \
                       "in proportion to table size.",
              suggestion: <<~SUGGESTION.chomp
                Alternatives:
                  - TABLESAMPLE: SELECT * FROM t TABLESAMPLE SYSTEM (1) LIMIT n
                  - random primary-key range: WHERE id >= (SELECT (random() * max(id))::bigint FROM t) LIMIT n
              SUGGESTION
            )
          end
        end
        detections
      end
    end
  end
end
