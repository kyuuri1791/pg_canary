# frozen_string_literal: true

module PgCanary
  # Helpers over the pg_query protobuf AST — the unwrapping, traversal and
  # value extraction the pg_query gem does not provide itself. Mix into
  # anything that inspects parsed queries (include for instance level,
  # extend for class level).
  module PgQuerySupport
    COMPARISON_OPS = %w[= <> != < > <= >=].freeze

    private

    # --- unwrapping wrapper nodes -------------------------------------

    # Unwraps a PgQuery::Node (oneof wrapper) into its inner message.
    def unwrap_node(node)
      return nil if node.nil?
      return node unless node.is_a?(PgQuery::Node)

      node.node ? node.inner : nil
    end

    # Strips TypeCast wrappers: `'foo'::text` → the A_Const for 'foo'.
    def strip_type_casts(node)
      node = unwrap_node(node)
      node = unwrap_node(node.arg) while node.is_a?(PgQuery::TypeCast)
      node
    end

    # --- traversal ----------------------------------------------------

    # Depth-first walk over every protobuf message under +node+, yielding
    # each unwrapped message. When +prune+ returns true for a message, it is
    # yielded but its children are not visited.
    def walk_ast(node, prune: nil, &block)
      node = unwrap_node(node)
      return if node.nil?
      return unless node.is_a?(Google::Protobuf::MessageExts)

      yield node
      return if prune&.call(node)

      each_ast_child(node) { |child| walk_ast(child, prune: prune, &block) }
    end

    # Yields every message-typed child of a protobuf message.
    def each_ast_child(node, &block)
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

    # Walk that does not descend into nested sub-selects, so each scope is
    # analyzed exactly once. Yielding starts at the given node's children,
    # i.e. pass a where_clause / sort item, not a whole statement.
    def walk_within_scope(node, &)
      root_seen = false
      walk_ast(node, prune: lambda { |msg|
        if root_seen
          msg.is_a?(PgQuery::SelectStmt)
        else
          root_seen = true # never prune the root itself
          false
        end
      }, &)
    end

    # --- reading values out of nodes ----------------------------------

    # ["users", "name"] for "users"."name"; nil when the ref contains A_Star.
    def column_ref_fields(column_ref)
      fields = column_ref.fields.map { |f| unwrap_node(f) }
      return nil unless fields.all?(PgQuery::String)

      fields.map(&:sval)
    end

    def string_values(nodes)
      nodes.map { |n| unwrap_node(n) }.grep(PgQuery::String).map(&:sval)
    end

    # Operator name of an A_Expr, e.g. "=", "~~", "~~*".
    def operator_name(a_expr)
      string_values(a_expr.name).last
    end

    # Unqualified, downcased function name of a FuncCall.
    def function_name(func_call)
      string_values(func_call.funcname).last&.downcase
    end

    # Ruby value of an A_Const: Integer, Float, String, true/false or nil.
    def constant_value(a_const)
      case a_const.val
      when :ival then a_const.ival.ival
      when :fval then a_const.fval.fval.to_f
      when :sval then a_const.sval.sval
      when :boolval then a_const.boolval.boolval
      end
    end

    def comparison_expr?(a_expr)
      a_expr.kind == :AEXPR_OP && COMPARISON_OPS.include?(operator_name(a_expr))
    end
  end
end
