# frozen_string_literal: true

module PgCanary
  module Rules
    # Comparing an integer-family column with a numeric/float literal
    # (age = 1.5) makes PostgreSQL cast the *column* to numeric, which
    # disables its index. Restricted to cases provable from the AST alone.
    class ImplicitCast < Base
      default_enabled true

      using PgCanary::PgQueryRefinement

      INTEGER_TYPES = %w[smallint integer bigint].freeze
      NUMERIC_TYPE_NAMES = %w[numeric decimal float4 float8].freeze

      def check
        detections = []
        each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr) && node.comparison?

            detections << inspect_comparison(scope, node)
          end
        end
        detections.compact
      end

      private

        def inspect_comparison(scope, expr)
          left = expr.lexpr&.unwrap
          right = expr.rexpr&.unwrap

          column_ref, value = if left.is_a?(PgQuery::ColumnRef)
                                [left, right]
                              elsif right.is_a?(PgQuery::ColumnRef)
                                [right, left]
                              end
          return nil unless column_ref
          return nil unless numeric_literal?(value)

          table, column = scope.resolve(column_ref)
          return nil unless table && column
          return nil unless applicable_table?(table)

          type = column_type(table, column)
          return nil unless INTEGER_TYPES.include?(type)

          detection(
            table: table,
            columns: column,
            message: "Comparing #{table}.#{column} (#{type}) with a numeric literal implicitly " \
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
            type = node.type_name.names.string_values.last
            NUMERIC_TYPE_NAMES.include?(type) && node.strip_casts.is_a?(PgQuery::A_Const)
          else
            false
          end
        end
    end
  end
end
