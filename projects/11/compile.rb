#!/usr/bin/env ruby

require 'json'

class JackTokenizer
  attr_accessor :tokens

  def initialize(filename)
    @@seq = 1
    @@found_literal = false
    contents = IO.read(filename)
    @tokens = tokenize(contents)
  end

  def to_xml
    <<-XML
      <tokens>
        #{@tokens.map(&:to_xml) * "\n"}
      </tokens>
    XML
  end

  def chartype(char)
    if @@found_literal || char == '"'
      @@found_literal = !@@found_literal if char == '"'
      return :stringConstant
    end
    case char
      when /[a-zA-Z0-9]/ then :alphanumeric
      when /\s/ then :whitespace
      else next_seq # hack because we don't want to chunk symbols together
    end
  end

  def next_seq
    @@seq += 1
  end

  def tokenize(contents)
    tokens = strip_excess_whitespace_and_comments(contents)
    tokens = tokens.chars.chunk(&method(:chartype))
    tokens = tokens.map { |x| Token.build(x.first, x.last * '') }
    tokens.reject { |c| c.name == :whitespace }
  end

  def strip_excess_whitespace_and_comments(str)
    str.gsub(/\/\*.*?\*\//m, '')
       .gsub(/\/\/.*?\n/, '')
       .gsub(/\n/, '')
       .gsub(/\r/, '')
       .gsub(/\s+/, ' ')
  end
end

class Token
  attr_accessor :name, :value, :escaped_value

  def initialize(name, value)
    @name, @value = name, value
    @escaped_value = escape_value(value)
  end

  class << self
    def datatypes
      %w[ int boolean char ]
    end

    def symbols
      %w[ { } [ ] ( ) . , ; _ ] + operators
    end

    def operators
      %w[ + - * / & | < > = ]
    end

    def keywords
      %w[ class method function constructor int boolean char void var static field let do if else while return true false null this ]
    end

    def build(name, value)
      xml_name = case
        when name.is_a?(Numeric) then :symbol
        when keywords.include?(value) then :keyword
        when name == :alphanumeric && value =~ /^[0-9]+$/ then :integerConstant
        when name == :alphanumeric then :identifier
        when name == :stringConstant then :stringConstant
        when name == :whitespace then name
        else :symbol
      end
      new(xml_name, value)
    end
  end

  def escape_value(val)
    escape_char_xref = { '>' => '&gt;', '<' => '&lt;', '"' => '&quot;', '&' => '&amp;' }
    remove_quotes_maybe(escape_char_xref[val] || val)
  end

  def remove_quotes_maybe(val)
    @name == :stringConstant ? val.tr('"', '') : val
  end

  def to_xml
    "<#@name> #@escaped_value </#@name>"
  end
end

class CompilationEngine
  class << self
    def compile(tokens)
      @@tokens = tokens
      @@symbol_table = SymbolTable.new
      compile_class
    end

    def symbol_table
      @@symbol_table
    end

    def nextsym
      @@tokens.slice!(0)
    end

    def nextidentifier
      val = nextsym
      if Token.datatypes.include?(val.value)
        raise "Unexpected type found: #{val.value}, expected identifier"
      elsif Token.symbols.include?(val.value)
        raise "Unexpected symbol found: #{val.value}, expected identifier"
      elsif Token.keywords.include?(val.value)
        raise "Unexpected keyword found: #{val.value}, expected identifier"
      end
      val
    end

    def nexttype
      optional_list(Token.datatypes) || nextidentifier
    end

    def optional_list(vals)
      if x = vals.find { |v| check(v) }
        optional(x)
      end
    end

    def one_of(vals)
      optional_list(vals) || begin
        raise "Value not found! Expected one of #{vals * ","}, got #{peek}"
      end
    end

    def expect(val)
      (check(val) && nextsym) || begin
        raise "Unexpected value, expected #{val}, got #{peek}"
      end
    end

    def check(val)
      peek == val
    end

    def peek_kind
      @@tokens.first.name
    end

    def peek
      @@tokens.first.value
    end

    def optional(val)
      nextsym if check(val)
    end

    def compile_class
      expect('class')
      @@classname = nextidentifier.value
      expect('{')
      compile_class_var_dec
      compile_subroutine
      expect('}')
    end

    def compile_subroutine
      types = %w[ method function constructor ]
      return unless types.include?(peek)

      subtype = one_of(types)
      optional_list(Token.datatypes + ['void']) || nextidentifier
      id = nextidentifier

      if subtype.value == 'method'
        @@symbol_table.define('this', @@classname, :arg)
      end

      expect('(')
      nargs = 0
      unless check(')')
        nargs += compile_parameter_list
      end
      expect(')')

      VMWriter.write_function(id.value, nargs)

      expect('{')
      compile_var_dec
      compile_statements
      expect('}')

      @@symbol_table.start_subroutine
      compile_subroutine
    end

    def compile_var_names(datatype, kind)
      id = nextidentifier
      @@symbol_table.define(id.value, datatype.value, kind.to_sym)
      if comma = optional(',')
        compile_var_names(datatype, kind)
      end
    end

    def compile_class_var_dec
      symbols = %w[ static field ]
      return unless symbols.include?(peek)

      sym = one_of(symbols)
      datatype = nexttype
      compile_var_names(datatype, sym.value)
      expect(';')
      compile_class_var_dec
    end

    def compile_parameter_list
      datatype = nexttype
      id = nextidentifier
      @@symbol_table.define(id.value, datatype.value, :arg)
      if comma = optional(',')
        return 1 + compile_parameter_list
      end

      return 1
    end

    def compile_var_dec
      return unless vartoken = optional('var')
      datatype = nexttype
      compile_var_names(datatype, vartoken.value)
      expect(';')
      compile_var_dec
    end

    def compile_statements
      map = {
        'let'    => -> { compile_let },
        'if'     => -> { compile_if },
        'while'  => -> { compile_while },
        'do'     => -> { compile_do },
        'return' => -> { compile_return },
      }
      while val = map[peek]
        val.()
      end
    end

    def compile_subroutine_call
      id = nextidentifier
      sym = one_of(%w[ ( . ])

      if sym.value == '.'
        other = nextidentifier
        expect('(')
      end

      compile_expression_list
      optional(')')
    end

    def compile_do
      expect("do")
      compile_subroutine_call
      expect(';')
    end

    def compile_let
      expect("let")
      nextidentifier
      if optional('[')
        compile_expression
        expect(']')
      end

      expect('=')
      compile_expression
      expect(';')
    end

    def compile_while
      l1 = @@symbol_table.nextlabel
      l2 = @@symbol_table.nextlabel

      expect("while")

      VMWriter.write_label l1

      expect('(')
      compile_expression

      VMWriter.write_arithmetic 'not'
      VMWriter.write_if l2

      expect(')')
      expect('{')
      compile_statements

      VMWriter.write_goto l1
      VMWriter.write_label l2
      expect('}')
    end

    def compile_return
      expect("return")
      compile_expression unless check(';')
      expect(';')
    end

    def compile_if
      expect("if")
      expect('(')
      compile_expression

      l1 = @@symbol_table.nextlabel
      l2 = @@symbol_table.nextlabel

      VMWriter.write_arithmetic 'not'
      VMWriter.write_if l1

      expect(')')
      expect('{')
      compile_statements
      expect('}')

      VMWriter.write_goto l2
      VMWriter.write_label l1

      if optional('else')
        expect('{')
        compile_statements
        expect('}')
      end

      VMWriter.write_label l2
    end

    def compile_expression
      compile_term
      while op = optional_list(Token.operators)
        compile_term.tap do
          VMWriter.write_arithmetic op.value
        end
      end
    end

    def compile_integer_constant
      if peek_kind == :integerConstant
        nextsym.tap do |s|
          VMWriter.write_push 'constant', s.value
        end
      end
    end

    def compile_string_constant
      if peek_kind == :stringConstant
        # TODO: how are strings represented?
      end
    end

    def compile_keyword_constant
      optional_list(%w[ true false null this ]).tap do |keyword|
        case keyword
          when 'true'
            VMWriter.write_push 'constant', '1'
            VMWriter.write_arithmetic 'neg'
          when 'false', 'null'
            VMWriter.write_push 'constant', '0'
          when 'this'
            # TODO: lookup this in symbol table?
            rec = @@symbol_table.lookup 'this'
            VMWriter.write_push rec.kind, rec.index
        end
      end
    end

    def compile_unary_op
      if op = optional_list(%w[ - ~ ])
        compile_term.tap do
          VMWriter.write_arithmetic op
        end
      end
    end

    def compile_parenthetical
      if optional('(')
        compile_expression
        expect(')')
      end
    end

    def compile_term
      compile_integer_constant or
        compile_string_constant or
        compile_keyword_constant or
        compile_unary_op or
        compile_parenthetical or
        begin
          id = nextidentifier
          case optional_list(%w{ [ ( . })
            when '[' # id == array
              # TODO: handle arrays
              compile_expression
              expect(']')
            when '(' # subroutine call; write call
              nargs = compile_expression_list
              expect(')')
              VMWriter.write_call id.value, nargs
            when '.' # id == var; write call
              method = nextidentifier
              expect('(')
              nargs = compile_expression_list
              expect(')')
              subroutine = [ id.value, method.value ] * "."
              VMWriter.write_call subroutine, nargs
            else # var; push value of var onto the stack
              rec = @@symbol_table.lookup(id.value)
              VMWriter.write_push rec.kind, rec.index
          end
        end
    end

    def compile_expression_list
      nargs = 0

      unless check(')')
        compile_expression
        nargs += 1
        while comma = optional(',')
          compile_expression
          nargs += 1
        end
      end

      return nargs
    end
  end
end

SymbolTableEntry = Struct.new(:name, :type, :kind, :index) do
  def to_s
    "name=#{name}, type=#{type}, kind=#{kind}, index=#{index}"
  end
end

class SymbolTable
  attr_accessor :class_scope, :subroutine_scope, :indices, :label_idx

  def initialize
    @class_scope, @subroutine_scope, @indices = {}, {}, {}
    @label_idx = 0
  end

  def nextlabel
    @label_idx += 1
    "LABEL#@label_idx"
  end

  def nextindex(kind)
    @indices[kind] ||= -1
    @indices[kind] += 1
  end

  def start_subroutine
    @subroutine_scope = {}
    subroutine_scope_types.each { |x| @indices[x] = -1 }
  end

  def class_scope_types
    [ :static, :field ]
  end

  def subroutine_scope_types
    [ :arg, :var ]
  end

  def get_scope_for(kind)
    if class_scope_types.include?(kind)
      @class_scope
    elsif subroutine_scope_types.include?(kind)
      @subroutine_scope
    else
      raise "Undefined kind: #{kind}"
    end
  end

  def define(name, type, kind)
    target = get_scope_for(kind)
    target[name] = SymbolTableEntry.new(name, type, kind, nextindex(kind))
  end

  def varcount(kind)
    @@indices[kind]
  end

  def lookup(name)
    @subroutine_scope[name] || @class_scope[name]
  end

  def kindof(name)
    x = lookup(name)
    x.nil? ? :none : x.kind
  end

  def typeof(name)
    lookup(name).type
  end

  def indexof(name)
    lookup(name).index
  end

  def to_s
    [
      @class_scope.values.map(&:to_s) * ",",
      @subroutine_scope.values.map(&:to_s) * ",",
    ] * " & "
  end
end

class VMWriter
  class << self
    def segment_map(x)
      { const: 'constant', arg: 'argument' }[x] || x.to_s
    end

    def write_push(segment, index)
      # segment = (const, arg, local, static, this, that, pointer, temp)
      write "push #{segment_map(segment)} #{index}"
    end

    def write_pop(segment, index)
      # segment = (const, arg, local, static, this, that, pointer, temp)
      write "pop #{segment_map(segment)} #{index}"
    end

    def write_arithmetic(command)
      # command = (add, sub, neg, eq, gt, lt, and, or, not)
      command_map = { '+' => 'add', '-' => 'sub', '~' => 'neg', '=' => 'eq', '>' => 'gt', '<' => 'lt', '&' => 'and', '|' => 'or', '~' => 'not' }
      write command_map[command]
    end

    def write_label(label)
      # label = string
      write "label #{label}"
    end

    def write_goto(label)
      # label = string
      write "goto #{label}"
    end

    def write_if(label)
      # label = string
      write "if-goto #{label}"
    end

    def write_call(name, nargs)
      # name = string
      # nargs = int
      write "call #{name} #{nargs}"
    end

    def write_function(name, nlocals)
      # name = string
      # nlocals = int
      write "function #{name} #{nlocals}"
    end

    def write_return
      write "return"
    end

    def write(line)
      puts line
    end
  end
end

class JackCompiler
  def self.compile(path_or_file)
    path = path_or_file + (path_or_file.include?(?.) ? '' : '*.jack')
    files = Dir[path]

    files.each do |filepath|
      tokenizer = JackTokenizer.new(filepath)
      CompilationEngine.compile(tokenizer.tokens)
      p CompilationEngine.symbol_table.to_s
    end
  end
end

JackCompiler.compile(ARGV.first)
