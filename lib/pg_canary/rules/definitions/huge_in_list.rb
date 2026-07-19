# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # IN (...) / = ANY(...) with a huge number of values: the statement
    # itself becomes expensive to parse/plan and usually signals a missing
    # JOIN. Counts literal list items and runtime array binds, which static
    # SQL linters cannot see.
    # Threshold: config.rules.huge_in_list.threshold (default 500).
    class HugeInList < Base
      default_enabled true
      option :threshold, default: 500

      def check(query)
        threshold = rule_config(query).threshold
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr)

            count = value_count(query, node)
            next unless count && count > threshold

            table, column = resolve_lexpr(scope, node)
            detections << detection(
              query,
              table: table,
              columns: column,
              message: "IN / ANY list with #{count} values (threshold: #{threshold}). Huge value lists " \
                       "are expensive to parse and plan, and usually mean a JOIN is missing.",
              suggestion: "Rewrite as a JOIN against the source of the values (subquery or VALUES list) " \
                          "instead of materializing the ids in the query."
            )
          end
        end
        detections
      end

      private

        def value_count(query, a_expr)
          case a_expr.kind
          when :AEXPR_IN
            list = a_expr.rexpr&.unwrap
            list.is_a?(PgQuery::List) ? list.items.length : nil
          when :AEXPR_OP_ANY
            param = a_expr.rexpr&.strip_casts
            return nil unless param.is_a?(PgQuery::ParamRef)

            value = query.bind_value(param.number)
            value.is_a?(Array) ? value.length : nil
          end
        end

        def resolve_lexpr(scope, a_expr)
          column_ref = a_expr.lexpr&.strip_casts
          return nil unless column_ref.is_a?(PgQuery::ColumnRef)

          scope.resolve(column_ref)
        end
    end
  end
end
