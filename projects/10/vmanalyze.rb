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
    # TODO how come flipflop doesn't work?
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

    def peek
      @@tokens.first.value
    end

    def optional(val)
      nextsym if check(val)
    end

    def compile_class
      expect('class')
      name = nextidentifier
      expect('{')
      vardecs = zero_or_more { compile_class_var_dec }
      subdecs = zero_or_more { compile_subroutine }
      expect('}')

      <<-XML
        <class>
          #{compile_keyword('class')}
          #{compile_identifier(name)}
          #{vardecs * "\n"}
          #{subdecs * "\n"}
        </class>
      XML
    end

    def compile_subroutine
      symbols = %w[ method function constructor ]
      return unless symbols.include?(peek)

      type = one_of(symbols)
      returntype = nextsym
      name = nextidentifier

      expect('(')
      params = compile_parameter_list
      expect(')')
      expect('{')
      vardecs = zero_or_more { compile_var_dec }
      body = compile_statements
      expect('}')

      <<-XML
        <subroutineDec>
          #{compile_keyword(type)}
          #{compile_identifier(returntype)}
          #{compile_identifier(name)}
          #{compile_symbol('(')}
          <parameterList>
            #{params}
          </parameterList>
          #{compile_symbol(')')}
          <subroutineBody>
            #{compile_symbol('{')}
            #{vardecs * "\n"}
            #{body}
            #{compile_symbol('}')}
          </subroutineBody>
        </subroutineDec>
      XML
    end

    def compile_var_names
      # TODO: use zero_or_more?
      names = []
      loop do
        names << compile_identifier(nextidentifier)
        comma = optional(',')
        if comma.nil?
          return names
        else
          names << compile_symbol(comma)
        end
      end
    end

    def compile_class_var_dec
      symbols = %w[ static field ]
      return unless symbols.include?(peek)

      type = one_of(symbols)
      datatype = nexttype
      names = compile_var_names
      expect(';')

      <<-XML
        <classVarDec>
          #{compile_keyword(type)}
          #{names * "\n"}
          #{compile_keyword(';')}
        </classVarDec>
      XML
    end

    def compile_parameter_list
      ''.tap do |result|
        return result if check(')')
        loop do
          result << compile_identifier(nexttype)
          result << compile_identifier(nextidentifier)
          break if check(')')
          result << compile_symbol(expect(','))
        end
      end
    end

    def compile_var_dec
      return unless optional('var')

      datatype = nexttype
      names = compile_var_names

      <<-XML
        <varDec>
          #{compile_keyword('var')}
          #{compile_keyword(datatype)}
          #{names * "\n"}
          #{compile_symbol(expect(';'))}
        </varDec>
      XML
    end

    def zero_or_more
      [].tap do |result|
        while val = yield
          return result if val.empty? # TODO is this necessary?
          result << val
        end
      end
    end

    def compile_statements
      map = {
        'let'    => -> { compile_let },
        'if'     => -> { compile_if },
        'while'  => -> { compile_while },
        'do'     => -> { compile_do },
        'return' => -> { compile_return },
      }
      # TODO: use zero or more?
      statements = []
      while val = map[peek]
        statements << val.()
      end
      <<-XML
        <statements>
          #{statements * "\n"}
        </statements>
      XML
    end

    def compile_subroutine_call
      # subroutineName '(' expressionList ')' | (className |
      # varName) '.' subroutineName '(' expressionList ')'

      # ((className | varName) '.')? subroutineName '(' expressionList ')'
      compiled_string = compile_identifier(nextidentifier)
      sym = one_of(%w[ ( . ])
      compiled_string += compile_symbol(sym)

      if sym == '.'
        compiled_string += compile_identifier(nextidentifier)
        compiled_string += compile_symbol(expect('('))
      end

      if rparen = optional(')')
        compiled_string += compile_symbol(rparen)
      else
        compiled_string += compile_expression_list
      end
      compiled_string += compile_symbol(expect(';')) # TODO: move to compile do?
    end

    def compile_do
      expect("do")
      compiled_string = compile_subroutine_call

      <<-XML
        <doStatement>
          #{compile_keyword('do')}
          #{compiled_string}
        </doStatement>
      XML
    end

    def compile_let
      expect("let")
      id = nextidentifier
      if subscript = optional('[')
        subscript = compile_symbol(subscript) + compile_expression + compile_symbol(expect(']'))
      end

      expect('=')

      <<-XML
        <letStatement>
          #{compile_keyword('let')}
          #{compile_identifier(id)}
          #{subscript}
          #{compile_symbol('=')}
          #{compile_expression}
          #{compile_symbol(expect(';'))}
        </letStatement>
      XML
    end

    def compile_while
      expect("while")
      expect('(')
      predicate = compile_expression
      expect(')')
      expect('{')
      whilestatements = compile_statements
      expect('}')
      <<-XML
        <whileStatement>
          #{compile_keyword('if')}
          #{compile_symbol('(')}
          #{predicate}
          #{compile_symbol(')')}
          #{compile_symbol('{')}
          #{whilestatements * "\n"}
          #{compile_symbol('}')}
        </whileStatement>
      XML
    end

    def compile_return
      exp = compile_keyword(expect("return"))
      if peek != ';'
        exp += compile_expression
      end
      exp += compile_symbol(expect(';'))
      #statement = nextsym
      #statement = if statement != ';'
      #  compile_expression(true) + compile_symbol(expect(';'))
      #else
      #  compile_symbol(';')
      #end

      <<-XML
        <returnStatement>
          #{exp}
        </returnStatement>
      XML
    end

    def compile_if
      expect("if")
      expect('(')
      predicate = compile_expression
      expect(')')
      expect('{')
      ifstatements = compile_statements
      expect('}')
      else_str = if peek == 'else'
        compile_keyword(expect('else')) + compile_symbol(expect('{')) + compile_statements + compile_symbol(expect('}'))
      else
        ''
      end

      <<-XML
        <ifStatement>
          #{compile_keyword('if')}
          #{compile_symbol('(')}
          #{predicate}
          #{compile_symbol(')')}
          #{compile_symbol('{')}
          #{ifstatements}
          #{compile_symbol('}')}
          #{else_str}
        </ifStatement>
      XML
    end

    def compile_expression
      # term (op term)*
      terms = compile_term
      while sym = optional_list(operators)
        terms += compile_symbol(sym) + compile_term
      end
      <<-XML
        <expression>
          #{terms}
        </expression>
      XML
    end

    def is_int(i)
      Integer(i) rescue nil
    end

    def compile_integer_constant
      if is_int(peek)
        nextsym
      end
    end

    def compile_string_constant
      # TODO: quotes aren't in the tokens
      if quote = optional('"')
        val = compile_symbol(quote) + nextidentifier + compile_symbol(expect('"'))
      end
    end

    def compile_keyword_constant
      if val = optional_list(%w[ true false null this ])
        compile_keyword(val)
      end
    end

    def compile_unary_op
      if sym = optional_list(%w[ - ~ ])
        compile_symbol(sym) + compile_term # TODO nested <term>?
      end
    end

    def compile_parenthetical
      if rparen = optional('(')
        compile_symbol(rparen) + compile_expression + compile_symbol(expect(')'))
      end
    end

    def compile_term
      # integerConstant | stringConstant | keywordConstant |
      # varName | varName '[' expression ']' | subroutineCall |
      # '(' expression ')' | unaryOp term
      term = compile_integer_constant || begin
        compile_string_constant || begin
          compile_keyword_constant || begin
            compile_unary_op || begin
              compile_parenthetical || begin
                str = compile_identifier(nextidentifier)
                str + if sym = optional_list(%w{ [ ( . })
                  compile_symbol(sym) + case sym
                    when '[' # id == array
                      compile_expression + compile_symbol(expect(']'))
                    when '(' # id == subroutine call
                      compile_expression_list + compile_symbol(expect(')'))
                    when '.' # id == variable
                      compile_identifier(nextidentifier) + compile_symbol(expect('(')) + compile_expression_list + compile_symbol(expect(')'))
                  end
                else
                  ''
                end
              end
            end
          end
        end
      end

      <<-XML
        <term>
          #{term}
        </term>
      XML
    end

    def compile_expression_list
      exp = compile_expression
      while comma = optional(',')
        exp += compile_symbol(comma) + compile_expression
      end
      <<-XML
        <expressionList>
          #{exp}
        </expressionList>
      XML
    end
  end
end

class JackAnalyzer
  def self.analyze(path_or_file)
    path = path_or_file + (path_or_file.include?(?.) ? '' : '*.jack')
    files = Dir[path]

    files.each do |filepath|
      tokenizer = JackTokenizer.new(filepath)
      #puts tokenizer.to_xml
      puts CompilationEngine.compile(tokenizer.tokens)
    end
  end
end

JackAnalyzer.analyze(ARGV.first)
