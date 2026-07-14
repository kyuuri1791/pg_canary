# frozen_string_literal: true

module PgCanary
  module Rules
    # Tier 2 (opt-in): OR conditions spanning different columns. PostgreSQL
    # can sometimes combine per-column indexes with a BitmapOr, so this is a
    # warning-level hint rather than a certainty.
    class OrAcrossColumns < Base
      def default_enabled
        false
      end

      def size_dependent?
        true
      end

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          seen = []
          walk_within_scope(scope.where_clause) do |node|
            next unless node.is_a?(PgQuery::BoolExpr) && node.boolop == :OR_EXPR

            columns = predicate_columns(query, scope, node)
            next if columns.length < 2
            next if seen.include?(columns)

            seen << columns
            detections << build(query, columns)
          end
        end
        detections
      end

      private

      # Distinct (table, column) pairs among the OR branches' simple
      # column-vs-constant predicates.
      def predicate_columns(query, scope, bool_expr)
        columns = bool_expr.args.filter_map do |arg|
          expr = unwrap_node(arg)
          next nil unless expr.is_a?(PgQuery::A_Expr)
          next nil unless comparison_expr?(expr) || %i[AEXPR_IN AEXPR_LIKE AEXPR_ILIKE].include?(expr.kind)

          column_ref = strip_type_casts(expr.lexpr)
          next nil unless column_ref.is_a?(PgQuery::ColumnRef)

          resolved = scope.resolve(column_ref)
          resolved if resolved && applicable_table?(query, resolved.first)
        end
        columns.uniq.sort
      end

      def build(query, columns)
        column_list = columns.map { |table, column| "#{table}.#{column}" }.join(", ")
        detection(
          query,
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
