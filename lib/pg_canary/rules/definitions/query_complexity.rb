# frozen_string_literal: true

module PgCanary
  module Rules
    # Tier 2 (opt-in): "spaghetti query" guard — too many joins or too much
    # subquery nesting. Thresholds:
    #   config.rules.query_complexity.max_joins (default 8)
    #   config.rules.query_complexity.max_depth (default 4)
    class QueryComplexity < Base
      def default_enabled
        false
      end

      def self.options
        { max_joins: 8, max_depth: 4 }
      end

      def check(query)
        max_joins = rule_config(query).max_joins
        max_depth = rule_config(query).max_depth
        stmt = query.parse_result.tree.stmts.first&.stmt
        return [] unless stmt

        problems = []
        joins = count_joins(stmt)
        depth = max_select_depth(stmt)
        problems << "#{joins} joins (max #{max_joins})" if joins > max_joins
        problems << "subquery depth #{depth} (max #{max_depth})" if depth > max_depth
        return [] if problems.empty?

        [detection(
          query,
          message: "Query complexity exceeds thresholds: #{problems.join(", ")}.",
          suggestion: "Consider splitting the query, precomputing intermediate results, " \
                      "or reviewing whether every join/subquery is necessary."
        )]
      end

      private

        def count_joins(stmt)
          joins = 0
          walk_ast(stmt) { |node| joins += 1 if node.is_a?(PgQuery::JoinExpr) }
          joins
        end

        # Maximum nesting depth of SELECT statements (a flat query is 1).
        def max_select_depth(node)
          node = unwrap_node(node)
          return 0 unless node.is_a?(Google::Protobuf::MessageExts)

          deepest_child = 0
          each_ast_child(node) do |child|
            depth = max_select_depth(child)
            deepest_child = depth if depth > deepest_child
          end
          (node.is_a?(PgQuery::SelectStmt) ? 1 : 0) + deepest_child
        end
    end
  end
end
