# frozen_string_literal: true

module PgCanary
  module Rules
    # Index and column metadata for the rules, read through ActiveRecord's
    # schema cache — caching, invalidation and thread safety ride on Rails.
    # The catalog queries ActiveRecord issues are named "SCHEMA", which the
    # Subscriber already ignores, so they are never analyzed themselves.
    module SchemaIntrospection
      IndexInfo = Struct.new(
        :name,        # index name
        :using,       # access method: "btree", "gin", "gist", ...
        :columns,     # [String] — empty for expression indexes
        :opclasses,   # { column => opclass } for non-default opclasses
        :expressions, # SQL string of the indexed expressions, or nil
        keyword_init: true
      ) do
        def leading_column
          columns.first
        end
      end

      module_function

      # => [IndexInfo] — includes the primary key, which ActiveRecord's
      # #indexes omits.
      def indexes(connection, table)
        cache = connection.schema_cache
        return [] unless cache.data_source_exists?(table)

        list = cache.indexes(table).map { |definition| index_info(definition) }
        primary_key = Array(cache.primary_keys(table))
        if primary_key.any?
          list << IndexInfo.new(name: "#{table}_pkey", using: "btree",
                                columns: primary_key, opclasses: {}, expressions: nil)
        end
        list
      rescue StandardError => e
        PgCanary.internal_error(e)
        []
      end

      def column_type(connection, table, column)
        column_types(connection, table)[column]
      end

      # => { column_name => sql_type } e.g. { "id" => "bigint", "tags" => "text[]" }
      def column_types(connection, table)
        cache = connection.schema_cache
        return {} unless cache.data_source_exists?(table)

        cache.columns(table).to_h do |column|
          type = column.sql_type
          type = "#{type}[]" if column.respond_to?(:array?) && column.array?
          [column.name, type]
        end
      rescue StandardError => e
        PgCanary.internal_error(e)
        {}
      end

      # ActiveRecord returns plain-column indexes with an Array of column
      # names, and expression indexes with the expressions as one SQL String.
      def index_info(definition)
        expressions = definition.columns.is_a?(String) ? definition.columns : nil
        columns = expressions ? [] : Array(definition.columns)
        opclasses = definition.opclasses
        opclasses = columns.to_h { |c| [c, opclasses.to_s] } unless opclasses.is_a?(Hash)
        IndexInfo.new(name: definition.name, using: definition.using.to_s,
                      columns: columns, opclasses: opclasses, expressions: expressions)
      end
    end
  end
end
