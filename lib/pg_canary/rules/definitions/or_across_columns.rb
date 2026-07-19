# frozen_string_literal: true

module PgCanary
  module Rules
    # OR conditions spanning different columns. PostgreSQL
    # can sometimes combine per-column indexes with a BitmapOr, so this is a
    # warning-level hint rather than a certainty.
    class OrAcrossColumns < Base
      default_enabled false

      using PgCanary::PgQueryRefinement

      def check
        detections = []
        each_scope do |scope|
          next unless scope.where_clause

          seen = []
          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::BoolExpr) && node.boolop == :OR_EXPR

            columns = predicate_columns(scope, node)
            next if columns.length < 2
            next if seen.include?(columns)

            seen << columns
            detections << build(columns)
          end
        end
        detections
      end

      private

        # Distinct (table, column) pairs among the OR branches' simple
        # column-vs-constant predicates.
        def predicate_columns(scope, bool_expr)
          columns = bool_expr.args.filter_map do |arg|
            expr = arg.unwrap
            next nil unless expr.is_a?(PgQuery::A_Expr)
            next nil unless expr.comparison? || %i[AEXPR_IN AEXPR_LIKE AEXPR_ILIKE].include?(expr.kind)

            column_ref = expr.lexpr&.strip_casts
            next nil unless column_ref.is_a?(PgQuery::ColumnRef)

            resolved = scope.resolve(column_ref)
            resolved if resolved && applicable_table?(resolved.first)
          end
          columns.uniq.sort
        end

        def build(columns)
          column_list = columns.map { |table, column| "#{table}.#{column}" }.join(", ")
          detection(
            table: columns.first.first,
            columns: columns.map(&:last),
            message: "OR across different columns (#{column_list}) often prevents a single index scan.",
            suggestion: "Ensure each column has its own index (PostgreSQL can then BitmapOr them), " \
                        "or split the query into a UNION of two indexed queries."
          )
        end
    end
  end
end
