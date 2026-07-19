# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # One SELECT scope (top-level statement, CTE, subquery, ...) with its
    # own FROM-clause alias resolution.
    class Scope
      attr_reader :stmt, :aliases

      def initialize(stmt)
        @stmt = stmt
        @aliases = {}
        collect_aliases(stmt.from_clause)
      end

      def where_clause
        stmt.where_clause
      end

      # => [PgQuery::SortBy]
      def sort_items
        stmt.sort_clause.map(&:unwrap).grep(PgQuery::SortBy)
      end

      def limited?
        !stmt.limit_count.nil?
      end

      # Real table names referenced directly in this scope's FROM clause.
      def tables
        @aliases.values.compact.uniq
      end

      # Resolves a ColumnRef to [table, column]. Returns nil when the ref
      # cannot be attributed to a real table unambiguously (unknown alias,
      # subquery output, multiple candidate tables for an unqualified ref).
      def resolve(column_ref)
        fields = column_ref.field_names
        return nil if fields.nil? || fields.empty?

        column = fields.last
        if fields.length >= 2
          table = @aliases[fields[-2]]
          table ? [table, column] : nil
        else
          tables.length == 1 ? [tables.first, column] : nil
        end
      end

      private

        def collect_aliases(from_clause)
          from_clause.each { |node| collect_from_node(node.unwrap) }
        end

        def collect_from_node(node)
          case node
          when PgQuery::RangeVar
            name = node.alias&.aliasname
            name = node.relname if name.nil? || name.empty?
            @aliases[name] = node.relname
          when PgQuery::JoinExpr
            collect_from_node(node.larg&.unwrap)
            collect_from_node(node.rarg&.unwrap)
          when PgQuery::RangeSubselect
            name = node.alias&.aliasname
            @aliases[name] = nil if name && !name.empty?
          end
        end
    end
  end
end
