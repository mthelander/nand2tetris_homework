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
      return '' if tokens.empty?
      curr, *remaining_tokens = tokens
      p curr
      case curr.name
        when :keyword
          case curr.value
            when 'class'
              compile_class(remaining_tokens)
            when 'method', 'function', 'constructor'
              compile_subroutine(curr.value, remaining_tokens)
            when 'var'
              compile_var_dec(remaining_tokens)
            when 'static', 'field'
              compile_class_var_dec(curr.value, remaining_tokens)
            when 'let'
              compile_let(remaining_tokens)
            when 'do'
              compile_do(remaining_tokens)
            when 'if'
              compile_if(remaining_tokens)
            when 'while'
              compile_while(remaining_tokens)
            when 'return'
              compile_return(remaining_tokens)
            when 'else', 'true', 'false', 'null', 'this', 'int', 'boolean', 'char', 'void'
              compile_keyword(curr.value) + compile(remaining_tokens)
          end
        when :integerConstant, :stringConstant
          xml_value(curr.name.to_s, curr.value)
        when :identifier
          compile_identifier(curr.value)
        when :symbol
          case curr.value
            when '('
              compile_term(remaining_tokens)
            when '{'
              compile_term(remaining_tokens)
            else
              compile_symbol(curr.value)
            end
      end
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

    def parse_params_and_body(tokens)
      params, tail = balanced_partition('(', ')', tokens)
      body, rest = balanced_partition('{', '}', tail)
      return [ params, body, rest ]
    end

    def partition(val, tokens)
      head = slice_until(val, tokens)
      tail = tokens[head.size..-1]
      return [ head, tail ]
    end

    def slice_until(target, tokens)
      index = tokens.find_index { |t| t.value == target }
      tokens[0..index]
    end

    def balanced_partition(open, close, tokens)
      return [] if tokens.empty?
      idx = find_closing_char(open, close, tokens[1..-1])
      head = tokens[0..idx]
      tail = tokens[idx..-1]
      return [ head, tail ]
    end

    def find_closing_char(opening, closing, tokens)
      num_opening = 0

      tokens.each_with_index do |token, i|
        if token.value.to_s == opening
          num_opening += 1
        elsif token.value.to_s == closing
          return i if num_opening < 1
          num_opening -= 1
        end
      end

      #raise tokens.map(&:value).join(" ").inspect
      #raise "No matching #{closing} found!"
    end

    def compile_class(tokens)
      name, *statements = tokens
      <<-XML
        <class>
          #{compile_keyword('class')}
          #{compile_identifier(name)}
          #{compile_statements(statements)}
        </class>
      XML
    end

    def compile_subroutine(type, tokens)
      returntype, name, *rest = tokens
      params, body, other_tokens = parse_params_and_body(rest)

      <<-XML
        <subroutineDec>
          #{compile_keyword(type)}
          #{compile_identifier(returntype)}
          #{compile_identifier(name)}
          #{compile_parameter_list(params)}
          <subroutineBody>
            #{compile_statements(body)}
          </subroutineBody>
        </subroutineDec>

        #{compile(other_tokens)}
      XML
    end

    def compile_class_var_dec(type, tokens)
      line, rest = partition(';', tokens)
      datatype, *names_list = line
      symbols = [ ';', ',' ]
      compiled_list = names_list.map do |x|
        val = x.value
        symbols.include?(val) ? compile_symbol(val) : compile_identifier(val)
      end
      <<-XML
        <classVarDec>
          #{compile_keyword(type)}
          #{compiled_list}
        </classVarDec>
        #{compile(rest)}
      XML
    end

    def compile_parameter_list(tokens)
      line, rest = balanced_partition('(', ')', tokens)
      contents = line[1..-2]
      compiled_line = contents.map { |x| compile([x]) }
      <<-XML
        #{compile_symbol('(')}
        <parameterList>
          #{compiled_line * "\n"}
        </parameterList>
        #{compile_symbol(')')}

        #{compile(rest)}
      XML
    end

    def compile_var_dec(tokens)
      line, rest = partition(';', tokens)
      datatype, *names_list = line
      compiled_names = names_list.map { |x| compile([x]) } # TODO compile individually?
      <<-XML
        <varDec>
          #{compile_keyword('var')}
          #{compiled_names * "\n"}
          #{compile_symbol(';')}
        </varDec>

        #{compile(rest)}
      XML
    end

    def compile_statements(tokens)
      curly_brace, *rest = tokens
      idx = find_closing_char('{', '}', rest[1..-1])
      statements = rest[0..idx]
      other_tokens = rest[idx..-1]

      <<-XML
        #{compile_symbol('{')}

        <statements>
          #{compile(tokens[1..-1])}
        </statements>

        #{compile_symbol('}')}

        #{compile(other_tokens)}
      XML
    end

    def compile_do(tokens)
      line, rest = partition(';', tokens)

      <<-XML
        <doStatement>
          #{compile_keyword('do')}
          #{compile(line)}
        </doStatement>

        #{compile(rest)}
      XML
    end

    def compile_let(tokens)
      line, rest = partition(';', tokens)

      <<-XML
        <letStatement>
          #{compile_keyword('let')}
          #{compile(line)}
        </letStatement>

        #{compile(rest)}
      XML
    end

    def compile_while(tokens)
      idx = find_closing_char('(', ')', tokens[1..-1])
      predicate = tokens[0..idx]
      statementidx = find_closing_char('{', '}', tokens[idx..-1])
      statements = tokens[idx..statementidx]
      rest = tokens[statementidx..-1]

      <<-XML
        <whileStatement>
          #{compile_keyword('while')}
          #{compile_expression(predicate)}
          #{compile_statements(statements)}
        </whileStatement>

        #{compile(rest)}
      XML
    end

    def compile_return(tokens)
      statement, rest = partition(';', tokens)
      <<-XML
        <returnStatement>
          #{compile_keyword('return')}
          #{compile(statement)}
        </returnStatement>
        #{compile(rest)}
      XML
    end

    def compile_if(tokens)
      idx = find_closing_char('(', ')', tokens[1..-1])
      predicate = tokens[0..idx]
      statementidx = find_closing_char('{', '}', tokens[idx..-1])
      statements = tokens[idx..statementidx]
      rest = tokens[statementidx..-1]

      <<-XML
        <ifStatement>
          #{compile_keyword('if')}
          #{compile_expression(predicate)}
          #{compile_statements(statements)}
        </ifStatement>

        #{compile(rest)}
      XML
    end

    def compile_expression(tokens)
      ""
    end

    def compile_term(tokens)
      ""
    end

    def compile_expression_list(tokens)
      ""
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
