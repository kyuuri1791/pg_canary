# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # A column wrapped in a function inside WHERE (lower(email) = ?,
    # date(created_at) = ?) can never use a plain index on that column.
    # Silent when a matching expression index (same function, same column)
    # exists.
    class FunctionOnColumn < Base
      def default_enabled
        true
      end

      CHECKED_KINDS = %i[AEXPR_OP AEXPR_LIKE AEXPR_ILIKE AEXPR_IN AEXPR_BETWEEN].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr) && CHECKED_KINDS.include?(node.kind)

            [node.lexpr, node.rexpr].each do |side|
              detections << inspect_side(query, scope, side)
            end
          end
        end
        detections.compact
      end

      private

        # The first ColumnRef inside the function call (arguments may nest,
        # e.g. lower(trim(email))).
        def first_column_ref(node)
          found = nil
          node.walk_scope do |msg|
            found ||= msg if msg.is_a?(PgQuery::ColumnRef)
          end
          found
        end

        def inspect_side(query, scope, side)
          func = side&.strip_casts
          return nil unless func.is_a?(PgQuery::FuncCall)

          column_ref = first_column_ref(func)
          return nil unless column_ref

          table, column = scope.resolve(column_ref)
          return nil unless table && column
          return nil unless applicable_table?(query, table)

          func_name = func.function_name
          return nil if expression_index?(query, table, column, func_name)

          detection(
            query,
            table: table,
            columns: column,
            message: "#{table}.#{column} is wrapped in #{func_name}() inside WHERE, " \
                     "so a plain index on #{column} cannot be used.",
            suggestion: <<~SUGGESTION.chomp
              Consider adding an expression index:
                CREATE INDEX index_#{table}_on_#{func_name}_#{column} ON #{table} ((#{func_name}(#{column})));
            SUGGESTION
          )
        end

        # Matches by (function name, column name) word match against the index
        # expression SQL — a deliberate approximation that already avoids the
        # common false positives.
        def expression_index?(query, table, column, func_name)
          query.indexes(table).any? do |index|
            expressions = index.expressions
            next false unless expressions

            expressions.match?(/\b#{Regexp.escape(func_name)}\s*\(/i) &&
              expressions.match?(/\b#{Regexp.escape(column)}\b/)
          end
        end
    end
  end
end
