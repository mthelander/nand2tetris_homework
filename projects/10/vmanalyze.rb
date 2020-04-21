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

  def self.keyword?(str)
    keywords = %w[ class method function constructor int boolean char void var static field let do if else while return true false null this ]
    keywords.include?(str.downcase)
  end

  def self.build(name, value)
    xml_name = case
      when name.is_a?(Numeric) then :symbol
      when keyword?(value) then :keyword
      when name == :alphanumeric && value =~ /^[0-9]+$/ then :integerConstant
      when name == :alphanumeric then :identifier
      when name == :stringConstant then :stringConstant
      when name == :whitespace then name
      else :symbol
    end
    new(xml_name, value)
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
      puts x.kind_of?(Array) ? x * "\n" : x
      x
    end

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
      %w[ class constructor function method field static var true false null this let do if else while return void ]
    end

    def xml_value(tagname, value)
      "<#{tagname}>#{value}</#{tagname}>"
    end

    def compile_keyword(value)
      xml_value('keyword', value)
    end

    def compile_identifier(value)
      xml_value('identifier', value)
    end

    def compile_symbol(value)
      xml_value('symbol', value)
    end

    def nextsym
      @@tokens.slice!(0).value
    end

    def nextidentifier
      val = nextsym
      if datatypes.include?(val)
        raise "Unexpected type found: #{val}, expected identifier"
      elsif symbols.include?(val)
        raise "Unexpected symbol found: #{val}, expected identifier"
      elsif keywords.include?(val)
        raise "Unexpected keyword found: #{val}, expected identifier"
      end
      val
    end

    def nexttype
      optional_list(datatypes) || nextidentifier
    end

    def optional_list(vals)
      vals.find { |v| optional(v) }
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
      emit compile_keyword(expect('class'))
      emit compile_identifier(nextidentifier)
      emit compile_symbol(expect('{'))
      compile_class_var_dec
      compile_subroutine
      emit compile_symbol(expect('}'))
      emit "</class>"
    end

    def compile_subroutine
      types = %w[ method function constructor ]
      return unless types.include?(peek)

      emit "<subroutineDec>"
      emit compile_keyword(one_of(types))
      emit compile_identifier(optional_list(datatypes + ['void']) || nextidentifier)
      emit compile_identifier(nextidentifier)

      emit compile_symbol(expect('('))
      emit "<parameterList>"
      unless check(')')
        compile_parameter_list
      end
      emit "</parameterList>"
      emit compile_symbol(expect(')'))
      emit "<subroutineBody>"
      emit compile_symbol(expect('{'))
      compile_var_dec
      emit compile_statements
      emit compile_symbol(expect('}'))
      emit "</subroutineBody>"
      emit "</subroutineDec>"
      compile_subroutine
    end

    def compile_var_names
      emit compile_identifier(nextidentifier)
      if comma = optional(',')
        emit compile_symbol(comma)
        compile_var_names
      end
    end

    def compile_class_var_dec
      symbols = %w[ static field ]
      return unless symbols.include?(peek)

      emit "<classVarDec>"
      emit compile_keyword(one_of(symbols))
      emit compile_identifier(nexttype)
      compile_var_names
      emit compile_symbol(expect(';'))
      emit "</classVarDec>"
      compile_class_var_dec
    end

    def compile_parameter_list
      emit compile_identifier(nexttype)
      emit compile_identifier(nextidentifier)
      if comma = optional(',')
        emit compile_symbol(comma)
        compile_parameter_list
      end
    end

    def compile_var_dec
      return unless optional('var')

      emit "<varDec>"
      emit compile_keyword('var')
      emit compile_keyword(nexttype)
      compile_var_names
      emit compile_symbol(expect(';'))
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
      emit compile_identifier(nextidentifier)
      sym = one_of(%w[ ( . ])
      emit compile_symbol(sym)

      if sym == '.'
        emit compile_identifier(nextidentifier)
        emit compile_symbol(expect('('))
      end

      if rparen = optional(')')
        emit compile_symbol(rparen)
      else
        compile_expression_list
        emit compile_symbol(optional(')'))
      end
    end

    def compile_do
      emit "<doStatement>"
      emit compile_keyword(expect("do"))
      compile_subroutine_call
      emit compile_symbol(expect(';'))
      emit "</doStatement>"
    end

    def compile_let
      emit "<letStatement>"
      emit compile_keyword(expect("let"))
      emit compile_identifier(nextidentifier)
      if subscript = optional('[')
        emit compile_symbol(subscript)
        emit compile_expression
        emit compile_symbol(expect(']'))
      end

      emit compile_symbol(expect('='))
      emit compile_expression
      emit compile_symbol(expect(';'))
      emit "</letStatement>"
    end

    def compile_while
      emit "<whileStatement>"
      emit compile_keyword(expect("while"))
      emit compile_symbol(expect('('))
      emit compile_expression
      emit compile_symbol(expect(')'))
      emit compile_symbol(expect('{'))
      compile_statements
      emit compile_symbol(expect('}'))
      emit "</whileStatement>"
    end

    def compile_return
      emit "<returnStatement>"
      emit compile_keyword(expect("return"))
      if peek != ';'
        compile_expression
      end
      emit compile_symbol(expect(';'))
      emit "</returnStatement>"
    end

    def compile_if
      emit "<ifStatement>"
      emit compile_keyword(expect("if"))
      emit compile_symbol(expect('('))
      compile_expression
      emit compile_symbol(expect(')'))
      emit compile_symbol(expect('{'))
      compile_statements
      emit compile_symbol(expect('}'))
      if peek == 'else'
        emit compile_keyword(expect('else')) + compile_symbol(expect('{')) + compile_statements + compile_symbol(expect('}'))
      end
      emit "</ifStatement>"
    end

    def compile_expression
      # term (op term)*
      emit "<expression>"
      compile_term
      while sym = optional_list(operators)
        emit compile_symbol(sym)
        compile_term
      end
      emit "</expression>"
    end

    def compile_integer_constant
      if peek_kind == :integerConstant
        emit xml_value("integerConstant", nextsym)
      end
    end

    def compile_string_constant
      if peek_kind == :stringConstant
        emit xml_value("stringConstant", nextsym)
      end
    end

    def compile_keyword_constant
      if val = optional_list(%w[ true false null this ])
        emit compile_keyword(val)
      end
    end

    def compile_unary_op
      if sym = optional_list(%w[ - ~ ])
        emit compile_symbol(sym)
        compile_term # TODO nested <term>?
      end
    end

    def compile_parenthetical
      if lparen = optional('(')
        emit compile_symbol(lparen)
        compile_expression
        emit compile_symbol(expect(')'))
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
          emit compile_identifier(nextidentifier)
          if sym = optional_list(%w{ [ ( . })
            emit compile_symbol(sym)
            case sym
              when '[' # id == array
                compile_expression
                emit compile_symbol(expect(']'))
              when '(' # id == subroutine call
                if rparen = optional(')')
                  emit compile_symbol(rparen)
                else
                  compile_expression_list
                  emit compile_symbol(expect(')'))
                end
              when '.' # id == variable
                emit compile_identifier(nextidentifier)
                emit compile_symbol(expect('('))
                if rparen = optional(')')
                  emit compile_symbol(rparen)
                else
                  compile_expression_list
                  emit compile_symbol(expect(')'))
                end
            end
          end
        end

      emit "</term>"
    end

    def compile_expression_list
      emit "<expressionList>"
      compile_expression
      while comma = optional(',')
        emit compile_symbol(comma)
        compile_expression
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
      puts CompilationEngine.compile(tokenizer.tokens)
    end
  end
end

JackAnalyzer.analyze(ARGV.first)
