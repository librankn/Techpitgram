# frozen_string_literal: true

module RuboCop
  module Cop
    module Performance
      # This cop identifies places where inefficient `readlines` method
      # can be replaced by `each_line` to avoid fully loading file content into memory.
      #
      # @example
      #
      #   # bad
      #   File.readlines('testfile').each { |l| puts l }
      #   IO.readlines('testfile', chomp: true).each { |l| puts l }
      #
      #   conn.readlines(10).map { |l| l.size }
      #   file.readlines.find { |l| l.start_with?('#') }
      #   file.readlines.each { |l| puts l }
      #
      #   # good
      #   File.open('testfile', 'r').each_line { |l| puts l }
      #   IO.open('testfile').each_line(chomp: true) { |l| puts l }
      #
      #   conn.each_line(10).map { |l| l.size }
      #   file.each_line.find { |l| l.start_with?('#') }
      #   file.each_line { |l| puts l }
      #
      class IoReadlines < Cop
        include RangeHelp

        MSG = 'Use `%<good>s` instead of `%<bad>s`.'
        ENUMERABLE_METHODS = (Enumerable.instance_methods + [:each]).freeze

        def_node_matcher :readlines_on_class?, <<~PATTERN
          $(send $(send (const nil? {:IO :File}) :readlines ...) #enumerable_method?)
        PATTERN

        def_node_matcher :readlines_on_instance?, <<~PATTERN
          $(send $(send ${nil? !const_type?} :readlines ...) #enumerable_method? ...)
        PATTERN

        def on_send(node)
          readlines_on_class?(node) do |enumerable_call, readlines_call|
            offense(node, enumerable_call, readlines_call)
          end

          readlines_on_instance?(node) do |enumerable_call, readlines_call, _|
            offense(node, enumerable_call, readlines_call)
          end
        end

        def autocorrect(node)
          readlines_on_instance?(node) do |enumerable_call, readlines_call, receiver|
            # We cannot safely correct `.readlines` method called on IO/File classes
            # due to its signature and we are not sure with implicit receiver
            # if it is called in the context of some instance or mentioned class.
            return if receiver.nil?

            lambda do |corrector|
              range = correction_range(enumerable_call, readlines_call)

              if readlines_call.arguments?
                call_args = build_call_args(readlines_call.arguments)
                replacement = "each_line(#{call_args})"
              else
                replacement = 'each_line'
              end

              corrector.replace(range, replacement)
            end
          end
        end

        private

        def enumerable_method?(node)
          ENUMERABLE_METHODS.include?(node.to_sym)
        end

        def offense(node, enumerable_call, readlines_call)
          range = offense_range(enumerable_call, readlines_call)
          good_method = build_good_method(enumerable_call)
          bad_method = build_bad_method(enumerable_call)

          add_offense(
            node,
            location: range,
            message: format(MSG, good: good_method, bad: bad_method)
          )
        end

        def offense_range(enumerable_call, readlines_call)
          readlines_pos = readlines_call.loc.selector.begin_pos
          enumerable_pos = enumerable_call.loc.selector.end_pos
          range_between(readlines_pos, enumerable_pos)
        end

        def build_good_method(enumerable_call)
          if enumerable_call.method?(:each)
            'each_line'
          else
            "each_line.#{enumerable_call.method_name}"
          end
        end

        def build_bad_method(enumerable_call)
          "readlines.#{enumerable_call.method_name}"
        end

        def correction_range(enumerable_call, readlines_call)
          begin_pos = readlines_call.loc.selector.begin_pos

          end_pos = if enumerable_call.method?(:each)
                      enumerable_call.loc.expression.end_pos
                    else
                      enumerable_call.loc.dot.begin_pos
                    end

          range_between(begin_pos, end_pos)
        end

        def build_call_args(call_args_node)
          call_args_node.map(&:source).join(', ')
        end
      end
    end
  end
end
