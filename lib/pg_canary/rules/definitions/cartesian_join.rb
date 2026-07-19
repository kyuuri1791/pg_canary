# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # A JOIN with no join condition — an explicit CROSS JOIN between real
    # tables, or a comma join whose WHERE clause never connects the tables —
    # produces a cross product whose row count is the product of both sides.
    class CartesianJoin < Base
      default_enabled true

      def check
        detections = []
        each_scope do |scope|
          scope.stmt.from_clause.each do |item|
            each_join(item.unwrap) do |join|
              detections << join_detection(join) if unconditioned?(join)
            end
          end
          detections << comma_detection(scope) if comma_cartesian?(scope)
        end
        detections
      end

      private

        def each_join(node, &)
          return unless node.is_a?(PgQuery::JoinExpr)

          yield node
          each_join(node.larg&.unwrap, &)
          each_join(node.rarg&.unwrap, &)
        end

        def unconditioned?(join)
          join.jointype == :JOIN_INNER &&
            join.quals.nil? &&
            !join.is_natural &&
            join.using_clause.empty? &&
            real_table?(join.rarg) &&
            joinable_side?(join.larg)
        end

        # Restrict to joins between real tables so that deliberate cross joins
        # against functions (generate_series etc.) stay silent.
        def real_table?(node)
          node&.unwrap.is_a?(PgQuery::RangeVar)
        end

        def joinable_side?(node)
          inner = node&.unwrap
          inner.is_a?(PgQuery::RangeVar) || inner.is_a?(PgQuery::JoinExpr)
        end

        # FROM a, b (2+ plain tables) with no column-to-column equality in WHERE.
        def comma_cartesian?(scope)
          plain_tables = scope.stmt.from_clause.map(&:unwrap).grep(PgQuery::RangeVar)
          return false if plain_tables.length < 2

          !cross_table_equality?(scope)
        end

        def cross_table_equality?(scope)
          return false unless scope.where_clause

          found = false
          scope.where_clause.walk_scope do |node|
            next unless node.is_a?(PgQuery::A_Expr) && node.comparison?

            left = node.lexpr&.unwrap
            right = node.rexpr&.unwrap
            next unless left.is_a?(PgQuery::ColumnRef) && right.is_a?(PgQuery::ColumnRef)

            left_table, = scope.resolve(left)
            right_table, = scope.resolve(right)
            found ||= left_table && right_table && left_table != right_table
          end
          found
        end

        def join_detection(join)
          tables = [join.larg, join.rarg].map(&:unwrap)
                                         .grep(PgQuery::RangeVar).map(&:relname)
          build(tables)
        end

        def comma_detection(scope)
          build(scope.tables)
        end

        def build(tables)
          detection(
            table: tables.first,
            message: "JOIN between #{tables.join(" and ")} has no join condition, producing a cross " \
                     "product — the result grows with the product of both tables' row counts.",
            suggestion: "Add a join condition (ON / USING). If a cross product is really intended, " \
                        "add the table to config.ignore_tables to silence this."
          )
        end
    end
  end
end
