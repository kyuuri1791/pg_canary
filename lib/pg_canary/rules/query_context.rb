# frozen_string_literal: true

using PgCanary::PgQueryRefinement

module PgCanary
  module Rules
    # What a rule's #check receives: everything about one executed query —
    # the parsed AST (as Scopes), bind parameter values, the configuration,
    # and access to schema metadata via the connection the query ran on.
    class QueryContext
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

      attr_reader :sql, :connection, :parse_result, :config

      def initialize(sql:, connection:, parse_result:, config:, binds: [], type_casted_binds: nil)
        @sql = sql
        @connection = connection
        @parse_result = parse_result
        @config = config
        @binds = binds || []
        @type_casted_binds = type_casted_binds
      end

      # Cannot fail: a QueryContext is only built for SQL that already parsed.
      def fingerprint
        @fingerprint ||= PgQuery.fingerprint(sql)
      end

      # All SELECT scopes in the statement, including CTEs, subqueries in
      # FROM/WHERE and UNION branches.
      def scopes
        @scopes ||= begin
          stmts = []
          parse_result.tree.stmts.each do |raw|
            raw.stmt.walk { |msg| stmts << msg if msg.is_a?(PgQuery::SelectStmt) }
          end
          stmts.map { |s| Scope.new(s) }
        end
      end

      def each_scope(&)
        scopes.each(&)
      end

      # All real table names touched anywhere in the query.
      def tables
        @tables ||= scopes.flat_map(&:tables).uniq
      end

      # Value for a ParamRef ($n, 1-based). nil when unknown.
      def bind_value(number)
        index = number - 1
        return nil if index.negative?

        casted = @type_casted_binds
        return casted[index] if casted.is_a?(Array) && index < casted.length

        bind = @binds[index]
        return nil if bind.nil?

        bind.respond_to?(:value_for_database) ? bind.value_for_database : bind
      end

      # --- schema metadata for the query's connection ---

      def indexes(table)
        SchemaIntrospection.indexes(connection, table)
      end

      def column_type(table, column)
        SchemaIntrospection.column_type(connection, table, column)
      end

      # => { column_name => sql_type }
      def column_types(table)
        SchemaIntrospection.column_types(connection, table)
      end
    end
  end
end
