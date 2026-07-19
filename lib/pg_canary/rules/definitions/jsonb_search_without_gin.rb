# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # Searching a jsonb column in WHERE:
    # - containment/existence operators (@>, <@, ?, ?|, ?&) need a GIN index
    #   on the column
    # - key extraction (->> etc.) compared against a value needs a matching
    #   expression index
    class JsonbSearchWithoutGin < Base
      default_enabled true

      include IndexPredicates

      CONTAINMENT_OPS = %w[@> <@ ? ?| ?&].freeze
      EXTRACTION_OPS = %w[-> ->> #> #>>].freeze

      def check(query)
        detections = []
        query.each_scope do |scope|
          next unless scope.where_clause

          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr) && node.kind == :AEXPR_OP

            operator = node.operator
            if CONTAINMENT_OPS.include?(operator)
              detections << inspect_containment(query, scope, node, operator)
            elsif EXTRACTION_OPS.include?(operator)
              detections << inspect_extraction(query, scope, node, operator)
            end
          end
        end
        detections.compact
      end

      private

        def inspect_containment(query, scope, expr, operator)
          table, column = jsonb_column(query, scope, [expr.lexpr, expr.rexpr])
          return nil unless table
          return nil if gin_index_on?(query, table, column)

          detection(
            query,
            table: table,
            columns: column,
            message: "#{operator} search on jsonb column #{table}.#{column} has no GIN index " \
                     "and will scan every row in production.",
            suggestion: <<~SUGGESTION.chomp
              Consider a GIN index (jsonb_path_ops is smaller/faster if you only use @>):
                CREATE INDEX index_#{table}_on_#{column} ON #{table} USING gin (#{column});
            SUGGESTION
          )
        end

        def inspect_extraction(query, scope, expr, operator)
          table, column = jsonb_column(query, scope, [expr.lexpr])
          return nil unless table
          return nil if expression_index_referencing?(query, table, column)

          key = extraction_key(expr)
          expr_sql = "#{column} #{operator} #{key ? "'#{key}'" : "..."}"
          detection(
            query,
            table: table,
            columns: column,
            message: "Filtering on #{table}.#{expr_sql} has no matching expression index, " \
                     "so no index can serve this predicate.",
            suggestion: <<~SUGGESTION.chomp
              Consider an expression index on the extracted key:
                CREATE INDEX index_#{table}_on_#{column}_key ON #{table} ((#{expr_sql.sub("...", "'key'")}));
            SUGGESTION
          )
        end

        # First side that is a jsonb-typed, resolvable column.
        def jsonb_column(query, scope, sides)
          sides.each do |side|
            column_ref = side&.strip_casts
            next unless column_ref.is_a?(PgQuery::ColumnRef)

            table, column = scope.resolve(column_ref)
            next unless table && column
            next unless applicable_table?(query, table)
            next unless query.column_type(table, column) == "jsonb"

            return [table, column]
          end
          nil
        end

        def extraction_key(expr)
          const = expr.rexpr&.strip_casts
          return nil unless const.is_a?(PgQuery::A_Const)

          value = const.value
          value.is_a?(String) ? value : nil
        end
    end
  end
end
