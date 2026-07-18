# frozen_string_literal: true

module PgCanary
  module Rules
    # NOT IN (SELECT ...) is a double trap: if the subquery ever returns a
    # NULL the whole predicate yields no rows, and the planner cannot use an
    # anti-join as effectively as with NOT EXISTS.
    class NotInSubquery < Base
      def default_enabled
        true
      end

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          walk_within_scope(scope.where_clause) do |node|
            next unless not_expr?(node)

            node.args.each do |arg|
              sublink = unwrap_node(arg)
              next unless any_sublink?(sublink)

              detections << build(query, scope, sublink)
            end
          end
        end
        detections
      end

      private

      def not_expr?(node)
        node.is_a?(PgQuery::BoolExpr) && node.boolop == :NOT_EXPR
      end

      # x NOT IN (SELECT ...) parses as NOT(SubLink ANY, "=" test).
      def any_sublink?(node)
        return false unless node.is_a?(PgQuery::SubLink)
        return false unless node.sub_link_type == :ANY_SUBLINK

        operator = string_values(node.oper_name).last
        operator.nil? || operator == "="
      end

      def build(query, scope, sublink)
        test = strip_type_casts(sublink.testexpr)
        table, column = test.is_a?(PgQuery::ColumnRef) ? scope.resolve(test) : nil

        detection(
          query,
          table: table,
          columns: column,
          message: "NOT IN (SELECT ...) returns zero rows if the subquery yields even one NULL, " \
                   "and the planner optimizes it poorly compared to an anti-join — a classic slow query.",
          suggestion: <<~SUGGESTION.chomp
            Consider rewriting to NOT EXISTS:
              SELECT ... FROM t WHERE NOT EXISTS (SELECT 1 FROM sub WHERE sub.ref_id = t.id)
          SUGGESTION
        )
      end
    end
  end
end
