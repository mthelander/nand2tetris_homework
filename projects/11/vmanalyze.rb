#!/usr/bin/env ruby

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
    escape_char_xref = {
      '>' => '&gt;',
      '<' => '&lt;',
      '"' => '&quot;',
      '&' => '&amp;',
    }
    remove_quotes_maybe(escape_char_xref[val] || val)
  end

  def remove_quotes_maybe(val)
    if @name == :stringConstant
      val.tr('"', '')
    else
      val
    end
  end

  def to_xml
    "<#@name> #@escaped_value </#@name>"
  end
end

class CompilationEngine
  class << self
    def compile(tokens)
      @@tokens = tokens
      compile_class
    end

    def emit(x)
      (x.kind_of?(String) ? x : x.to_xml).tap(&method(:puts))
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
      compile_subroutine
    end

    def compile_var_names
      emit nextidentifier
      if comma = optional(',')
        emit comma
        compile_var_names
      end
    end

    def compile_class_var_dec
      symbols = %w[ static field ]
      return unless symbols.include?(peek)

      emit "<classVarDec>"
      emit one_of(symbols)
      emit nexttype
      compile_var_names
      emit expect(';')
      emit "</classVarDec>"
      compile_class_var_dec
    end

    def compile_parameter_list
      emit nexttype
      emit nextidentifier
      if comma = optional(',')
        emit comma
        compile_parameter_list
      end
    end

    def compile_var_dec
      return unless vartoken = optional('var')
      emit "<varDec>"
      emit vartoken
      emit nexttype
      compile_var_names
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

class JackAnalyzer
  def self.analyze(path_or_file)
    path = path_or_file + (path_or_file.include?(?.) ? '' : '*.jack')
    files = Dir[path]

    files.each do |filepath|
      tokenizer = JackTokenizer.new(filepath)
      CompilationEngine.compile(tokenizer.tokens)
    end
  end
end

JackAnalyzer.analyze(ARGV.first)
