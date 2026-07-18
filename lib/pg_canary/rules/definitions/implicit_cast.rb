# frozen_string_literal: true

module PgCanary
  module Rules
    # Comparing an integer-family column with a numeric/float literal
    # (age = 1.5) makes PostgreSQL cast the *column* to numeric, which
    # disables its index. Restricted to cases provable from the AST alone.
    class ImplicitCast < Base
      def default_enabled
        true
      end

      INTEGER_TYPES = %w[smallint integer bigint].freeze
      NUMERIC_TYPE_NAMES = %w[numeric decimal float4 float8].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          walk_within_scope(scope.where_clause) do |node|
            next unless node.is_a?(PgQuery::A_Expr) && comparison_expr?(node)

            detections << inspect_comparison(query, scope, node)
          end
        end
        detections.compact
      end

      private

      def inspect_comparison(query, scope, expr)
        left = unwrap_node(expr.lexpr)
        right = unwrap_node(expr.rexpr)

        column_ref, value = if left.is_a?(PgQuery::ColumnRef)
                              [left, right]
                            elsif right.is_a?(PgQuery::ColumnRef)
                              [right, left]
                            end
        return nil unless column_ref
        return nil unless numeric_literal?(value)

        table, column = scope.resolve(column_ref)
        return nil unless table && column
        return nil unless applicable_table?(query, table)

        column_type = query.column_type(table, column)
        return nil unless INTEGER_TYPES.include?(column_type)

        detection(
          query,
          table: table,
          columns: column,
          message: "Comparing #{table}.#{column} (#{column_type}) with a numeric literal implicitly " \
                   "casts the column to numeric, disabling any index on #{column}.",
          suggestion: "Use a literal that matches the column type (integer)."
        )
      end

      # A numeric/float literal, or an explicit cast to numeric of a literal.
      def numeric_literal?(node)
        case node
        when PgQuery::A_Const
          node.val == :fval
        when PgQuery::TypeCast
          type = string_values(node.type_name.names).last
          NUMERIC_TYPE_NAMES.include?(type) && strip_type_casts(node).is_a?(PgQuery::A_Const)
        else
          false
        end
      end
    end
  end
end
