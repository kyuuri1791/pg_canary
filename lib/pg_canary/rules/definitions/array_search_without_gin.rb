# frozen_string_literal: true

module PgCanary
  module Rules
    # Searching an array column (@>, <@, &&, or value = ANY(column)) without
    # a GIN index scans every row.
    class ArraySearchWithoutGin < Base
      include IndexPredicates

      def default_enabled
        true
      end

      ARRAY_OPS = %w[@> <@ &&].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          walk_within_scope(scope.where_clause) do |node|
            next unless node.is_a?(PgQuery::A_Expr)

            case node.kind
            when :AEXPR_OP
              operator = operator_name(node)
              next unless ARRAY_OPS.include?(operator)

              detections << inspect_sides(query, scope, [node.lexpr, node.rexpr], operator)
            when :AEXPR_OP_ANY
              detections << inspect_sides(query, scope, [node.rexpr], "= ANY(column)")
            end
          end
        end
        detections.compact
      end

      private

      def inspect_sides(query, scope, sides, operator)
        sides.each do |side|
          column_ref = strip_type_casts(side)
          next unless column_ref.is_a?(PgQuery::ColumnRef)

          table, column = scope.resolve(column_ref)
          next unless table && column
          next unless applicable_table?(query, table)
          next unless array_type?(query.column_type(table, column))
          next if gin_index_on?(query, table, column)

          return detection(
            query,
            table: table,
            columns: column,
            message: "Array search (#{operator}) on #{table}.#{column} has no GIN index " \
                     "and will scan every row in production.",
            suggestion: <<~SUGGESTION.chomp
              Consider a GIN index on the array column:
                CREATE INDEX index_#{table}_on_#{column} ON #{table} USING gin (#{column});
            SUGGESTION
          )
        end
        nil
      end

      def array_type?(sql_type)
        sql_type&.end_with?("[]")
      end
    end
  end
end
