# frozen_string_literal: true

module PgCanary
  module Rules
    # ORDER BY x LIMIT n without an index led by x forces a
    # full sort before the limit can apply. Size-dependent, so disabled by
    # default.
    class UnindexedOrderByWithLimit < Base
      default_enabled false

      include IndexPredicates

      using PgCanary::PgQueryRefinement

      def check
        detections = []
        each_scope do |scope|
          next unless scope.limited?

          sort_by = scope.sort_items.first
          next unless sort_by

          column_ref = sort_by.node&.unwrap
          next unless column_ref.is_a?(PgQuery::ColumnRef)

          table, column = scope.resolve(column_ref)
          next unless table && column
          next unless applicable_table?(table)
          next if index_leading_with?(table, column)

          detections << detection(
            table: table,
            columns: column,
            message: "ORDER BY #{column} LIMIT sorts every row before the limit can apply " \
                     "(no index on #{table} leads with #{column}).",
            suggestion: <<~SUGGESTION.chomp
              Consider indexing the sort key:
                CREATE INDEX index_#{table}_on_#{column} ON #{table} (#{column});
            SUGGESTION
          )
        end
        detections
      end
    end
  end
end
