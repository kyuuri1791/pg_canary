# frozen_string_literal: true

module PgCanary
  module PgQueryRefinement
    COMPARISON_OPS = %w[= <> != < > <= >=].freeze

    module Impl
      module_function

      def unwrap(node)
        return nil if node.nil?
        return node unless node.is_a?(PgQuery::Node)

        node.node ? node.inner : nil
      end

      def strip_casts(node)
        node = unwrap(node)
        node = unwrap(node.arg) while node.is_a?(PgQuery::TypeCast)
        node
      end

      def walk(node, prune: nil, &block)
        node = unwrap(node)
        return if node.nil?
        return unless node.is_a?(Google::Protobuf::MessageExts)

        yield node
        return if prune&.call(node)

        each_child(node) { |child| walk(child, prune: prune, &block) }
      end

      def each_child(node, &block)
        node.class.descriptor.each do |field|
          next unless field.type == :message

          value = node[field.name]
          next if value.nil?

          if value.is_a?(Google::Protobuf::RepeatedField)
            value.each(&block)
          else
            yield value
          end
        end
      end

      def walk_scope(node, &)
        root_seen = false
        walk(node, prune: lambda { |msg|
          if root_seen
            msg.is_a?(PgQuery::SelectStmt)
          else
            root_seen = true
            false
          end
        }, &)
      end

      def string_values(nodes)
        nodes.map { |n| unwrap(n) }.grep(PgQuery::String).map(&:sval)
      end
    end

    module MessageMethods
      def unwrap = self

      def walk(prune: nil, &) = Impl.walk(self, prune: prune, &)

      def walk_scope(&) = Impl.walk_scope(self, &)

      def each_child(&) = Impl.each_child(self, &)

      def strip_casts = Impl.strip_casts(self)
    end

    message_classes = PgQuery.constants
                             .map { |name| PgQuery.const_get(name) }
                             .grep(Class)
                             .select { |klass| klass < Google::Protobuf::MessageExts }

    message_classes.each do |klass|
      refine klass do
        import_methods MessageMethods
      end
    end

    refine PgQuery::Node do
      def unwrap = Impl.unwrap(self)
    end

    refine PgQuery::ColumnRef do
      def field_names
        unwrapped = fields.map { |f| Impl.unwrap(f) }
        return nil unless unwrapped.all?(PgQuery::String)

        unwrapped.map(&:sval)
      end
    end

    refine PgQuery::A_Expr do
      def operator = Impl.string_values(name).last

      def comparison? = kind == :AEXPR_OP && COMPARISON_OPS.include?(operator)
    end

    refine PgQuery::FuncCall do
      def function_name = Impl.string_values(funcname).last&.downcase
    end

    refine PgQuery::A_Const do
      def value
        case val
        when :ival then ival.ival
        when :fval then fval.fval.to_f
        when :sval then sval.sval
        when :boolval then boolval.boolval
        end
      end
    end

    refine Google::Protobuf::RepeatedField do
      def string_values = Impl.string_values(self)
    end
  end
end
