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

    def emit(x, attributes={})
      #if x.kind_of?(Token) && x.name == :identifier # && !category.empty?
      #  #type, category = attributes.values_at(:type, :category)
      #  #@@symbol_table.define(x.value, type, category)
      #  #puts { name: x.name type: type, category: category }.to_json
      #  puts @@symbol_table.lookup(x.value)
      #end
      x
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
        return optional(x)
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
      emit "<class>"
      emit expect('class')
      emit nextidentifier
      emit expect('{')
      compile_class_var_dec
      compile_subroutine
      emit expect('}')
      emit "</class>"
    end

    def compile_subroutine
      types = %w[ method function constructor ]
      return unless types.include?(peek)

      emit "<subroutineDec>"
      emit one_of(types)
      emit optional_list(Token.datatypes + ['void']) || nextidentifier
      emit nextidentifier

      emit expect('(')
      emit "<parameterList>"
      unless check(')')
        compile_parameter_list
      end
      emit "</parameterList>"
      emit expect(')')
      emit "<subroutineBody>"
      emit expect('{')
      compile_var_dec
      compile_statements
      emit expect('}')
      emit "</subroutineBody>"
      emit "</subroutineDec>"
      @@symbol_table.start_subroutine
      compile_subroutine
    end

    def compile_var_names(datatype, kind)
      id = nextidentifier
      @@symbol_table.define(id.value, datatype.value, kind.to_sym)
      if comma = optional(',')
        emit comma
        compile_var_names(datatype, kind)
      end
    end

    def compile_class_var_dec
      symbols = %w[ static field ]
      return unless symbols.include?(peek)

      emit "<classVarDec>"
      sym = one_of(symbols)
      emit sym
      datatype = nexttype
      emit datatype
      compile_var_names(datatype, sym.value)
      emit expect(';')
      emit "</classVarDec>"
      compile_class_var_dec
    end

    def compile_parameter_list
      datatype = nexttype
      emit datatype
      id = nextidentifier
      @@symbol_table.define(id.value, datatype.value, :arg)
      emit id
      if comma = optional(',')
        emit comma
        compile_parameter_list
      end
    end

    def compile_var_dec
      return unless vartoken = optional('var')
      emit "<varDec>"
      emit vartoken
      datatype = nexttype
      emit datatype
      compile_var_names(datatype, vartoken.value)
      emit expect(';')
      emit "</varDec>"
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
      emit "<statements>"
      while val = map[peek]
        val.()
      end
      emit "</statements>"
    end

    def compile_subroutine_call
      # subroutineName '(' expressionList ')' | (className |
      # varName) '.' subroutineName '(' expressionList ')'

      # ((className | varName) '.')? subroutineName '(' expressionList ')'
      emit nextidentifier
      sym = one_of(%w[ ( . ])
      emit sym

      if sym.value == '.'
        emit nextidentifier
        emit expect('(')
      end

      compile_expression_list
      emit optional(')')
    end

    def compile_do
      emit "<doStatement>"
      emit expect("do")
      compile_subroutine_call
      emit expect(';')
      emit "</doStatement>"
    end

    def compile_let
      emit "<letStatement>"
      emit expect("let")
      emit nextidentifier
      if subscript = optional('[')
        emit subscript
        compile_expression
        emit expect(']')
      end

      emit expect('=')
      compile_expression
      emit expect(';')
      emit "</letStatement>"
    end

    def compile_while
      emit "<whileStatement>"
      emit expect("while")
      emit expect('(')
      compile_expression
      emit expect(')')
      emit expect('{')
      compile_statements
      emit expect('}')
      emit "</whileStatement>"
    end

    def compile_return
      emit "<returnStatement>"
      emit expect("return")
      if peek != ';'
        compile_expression
      end
      emit expect(';')
      emit "</returnStatement>"
    end

    def compile_if
      emit "<ifStatement>"
      emit expect("if")
      emit expect('(')
      compile_expression
      emit expect(')')
      emit expect('{')
      compile_statements
      emit expect('}')
      if peek == 'else'
        emit expect('else')
        emit expect('{')
        compile_statements
        emit expect('}')
      end
      emit "</ifStatement>"
    end

    def compile_expression
      emit "<expression>"
      compile_term
      while sym = optional_list(Token.operators)
        emit sym
        compile_term
      end
      emit "</expression>"
    end

    def compile_integer_constant
      if peek_kind == :integerConstant
        emit nextsym
      end
    end

    def compile_string_constant
      if peek_kind == :stringConstant
        emit nextsym
      end
    end

    def compile_keyword_constant
      if val = optional_list(%w[ true false null this ])
        emit val
      end
    end

    def compile_unary_op
      if sym = optional_list(%w[ - ~ ])
        emit sym
        compile_term
      end
    end

    def compile_parenthetical
      if lparen = optional('(')
        emit lparen
        compile_expression
        emit expect(')')
      end
    end

    def compile_term
      emit "<term>"
      # integerConstant | stringConstant | keywordConstant |
      # varName | varName '[' expression ']' | subroutineCall |
      # '(' expression ')' | unaryOp term
      compile_integer_constant or
        compile_string_constant or
        compile_keyword_constant or
        compile_unary_op or
        compile_parenthetical or
        begin
          emit nextidentifier
          if sym = optional_list(%w{ [ ( . })
            emit sym
            case sym.value
              when '[' # id == array
                compile_expression
                emit expect(']')
              when '(' # id == subroutine call
                compile_expression_list
                emit expect(')')
              when '.' # id == variable
                emit nextidentifier
                emit expect('(')
                compile_expression_list
                emit expect(')')
            end
          end
        end

      emit "</term>"
    end

    def compile_expression_list
      emit "<expressionList>"
      unless check(')')
        compile_expression
        while comma = optional(',')
          emit comma
          compile_expression
        end
      end
      emit "</expressionList>"
    end
  end
end

SymbolTableEntry = Struct.new(:name, :type, :kind, :index) do
  def to_s
    "name=#{name}, type=#{type}, kind=#{kind}, index=#{index}"
  end
end

class SymbolTable
  attr_accessor :class_scope, :subroutine_scope, :indices

  def initialize
    @class_scope, @subroutine_scope, @indices = {}, {}, {}
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
    # TODO what is "the current scope"?
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
    def write_push(segment, index)
      # segment = (const, arg, local, static, this, that, pointer, temp)
    end

    def write_pop(segment, index)
      # segment = (const, arg, local, static, this, that, pointer, temp)
    end

    def write_arithmetic(command)
      # command = (add, sub, neg, eq, gt, lt, and, or, not)
    end

    def write_label(label)
      # label = string
    end

    def write_goto(label)
      # label = string
    end

    def write_if(label)
      # label = string
    end

    def write_call(name, nargs)
      # name = string
      # nargs = int
    end

    def write_function(name, nlocals)
      # name = string
      # nlocals = int
    end

    def write_return
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
