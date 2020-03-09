#!/usr/bin/env ruby

class VMParser
  attr_accessor :lines, :commands

  def initialize(filename)
    @lines = File.readlines(filename)
    @commands = @lines.map { |line| VMCommand.create(line, filename) }
  end
end

class VMCommand
  attr_accessor :line, :filename
  @@current_function = nil

  def initialize(line, filename)
    @line, @filename = line, filename
  end

  def to_hack_no_whitespace
    to_hack.split("\n").map(&:strip).reject(&:empty?).join("\n")
  end

  def to_hack
    ""
  end

  def line_tokens
    @line.split(' ')
  end

  class << self
    def get_class(vmline)
      case vmline
        when 'add'       then AddCommand
        when 'sub'       then SubCommand
        when 'eq'        then EqCommand
        when 'gt'        then GtCommand
        when 'lt'        then LtCommand
        when 'and'       then AndCommand
        when 'or'        then OrCommand
        when 'neg'       then NegCommand
        when 'not'       then NotCommand
        when /^push/     then PushCommand
        when /^pop/      then PopCommand
        when /^label/    then LabelCommand
        when /^goto/     then GotoCommand
        when /^if-goto/  then IfGotoCommand
        when /^call/     then CallCommand
        when /^function/ then FunctionCommand
        when 'return'    then ReturnCommand
        else VMCommand # no-op: comments and whitespace
      end
    end

    def create(line, filename)
      (vmline = line.split('//').first || "").strip!
      get_class(vmline).new(vmline, filename)
    end
  end
end

class BinaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      @SP
      M=M-1

      @SP
      A=M
      D=M

      @SP
      M=M-1

      @SP
      A=M
      #{operator_code}

      @SP
      M=M+1
    HACK
  end

  def operator_code
    'M=D-M'
  end
end

class UnaryOperatorCommand < VMCommand
  def to_hack
    <<-HACK
      @SP
      M=M-1

      @SP
      A=M
      M=#{operator}M

      @SP
      M=M+1
    HACK
  end
end

class AddCommand < BinaryOperatorCommand
  def operator_code
    'M=D+M'
  end
end

class SubCommand < BinaryOperatorCommand
  def operator_code
    <<-HACK
      D=-D
      M=D+M
    HACK
  end
end

class AndCommand < BinaryOperatorCommand
  def operator_code
    'M=D&M'
  end
end

class OrCommand < BinaryOperatorCommand
  def operator_code
    'M=D|M'
  end
end

class NegCommand < UnaryOperatorCommand
  def operator
    ?-
  end
end

class NotCommand < UnaryOperatorCommand
  def operator
    ?!
  end
end

class EqCommand < BinaryOperatorCommand
  @@address = 0

  def initialize(line, filename)
    @address = (@@address += 1)
    super
  end

  def jump_instruction
    'JEQ'
  end

  def operator_code
    <<-HACK
      D=-D
      D=D+M

      @TRUE#@address
      D;#{jump_instruction}

      @FALSE#@address
      0;JMP

      (TRUE#@address)
        @SP
        A=M
        M=0
        M=!M
        @END#@address
        0;JMP
      (FALSE#@address)
        @SP
        A=M
        M=0
        @END#@address
        0;JMP
      (END#@address)
    HACK
  end
end

class GtCommand < EqCommand
  def jump_instruction
    'JGT'
  end
end

class LtCommand < EqCommand
  def jump_instruction
    'JLT'
  end
end

class PushCommand < VMCommand
  TEMP_ADDRESS = 5

  def get_pointer_symbol(segment, index)
    case
      when segment == 'temp' then TEMP_ADDRESS + index
      when index == 0 then 'THIS'
      when segment == 'static' then [ File.basename(@filename, ".*"), index ] * ?.
      else'THAT'
    end
  end

  def symbol_map
    @symbol_map ||= {
      'local'    => 'LCL',
      'this'     => 'THIS',
      'that'     => 'THAT',
      'argument' => 'ARG',
    }
  end

  def offset_commands(index)
    (['A=A+1'] * index) * "\n"
  end

  def to_hack
    _, segment, index_str = line_tokens
    index = index_str.to_i

    arg_hack = case segment
      when 'constant'
        <<-HACK
          @#{index}
          D=A
        HACK
      when 'local', 'this', 'that', 'argument'
        symbol = symbol_map[segment] or raise "Invalid segment: #{segment}"
        <<-HACK
          @#{symbol}
          A=M
          #{offset_commands(index)}
          D=M
        HACK
      when 'temp', 'pointer', 'static'
        <<-HACK
          @#{get_pointer_symbol(segment, index)}
          D=M
        HACK
    end

    return <<-HACK
      // PUSH
      #{arg_hack}
      @SP
      A=M
      M=D
      @SP
      M=M+1
      // END PUSH
    HACK
  end
end

class PopCommand < PushCommand
  def to_hack
    _, segment, index_str = line_tokens
    index = index_str.to_i

    arg_hack = case segment
      when 'local', 'this', 'that', 'argument'
        symbol = symbol_map[segment] or raise "Invalid segment: #{segment}"
        <<-HACK
          @#{symbol}
          A=M
          #{offset_commands(index)}
          M=D
        HACK
      when 'temp', 'pointer', 'static'
        <<-HACK
          @#{get_pointer_symbol(segment, index)}
          M=D
        HACK
    end

    return <<-HACK
      // POP
      @SP
      M=M-1
      A=M
      D=M
      #{arg_hack}
      // END POP
    HACK
  end
end

class LabelCommand < VMCommand
  def label_symbol(name)
    # TODO: should this use Main?
    [ @@current_function || 'Main', name ] * ?$
  end

  def to_hack
    _, name = line_tokens
    "(#{label_symbol(name)})"
  end
end

class GotoCommand < LabelCommand
  def to_hack
    _, label_name = line_tokens
    label = label_symbol(label_name)
    <<-HACK
      @#{label}
      0;JMP
    HACK
  end
end

class IfGotoCommand < LabelCommand
  def to_hack
    _, label_name = line_tokens
    label = label_symbol(label_name)
    pop_code = PopCommand.new('pop', @filename).to_hack
    <<-HACK
      #{pop_code}
      @#{label}
      D;JGT
    HACK
  end
end

class FunctionCommand < VMCommand
  def to_hack
    _, func, nargs = line_tokens
    @@current_function = func
    init_pushes = [ PushCommand.new('push constant 0', @filename) ] * nargs.to_i
    <<-HACK
      (#@@current_function)
      #{init_pushes.map(&:to_hack) * "\n"}
    HACK
  end
end

class CallCommand < VMCommand
  @@address = 0

  def initialize(line, filename)
    # TODO: clean this up
    @address = (@@address += 1)
    super
  end

  def to_hack
    _, func, nargs = line_tokens
    return_address = "RETURN#@address"
    [
      PushCommand.new("push constant #{return_address}", @filename),
      PushCommand.new('push local 0', @filename),
      PushCommand.new('push argument 0', @filename),
      PushCommand.new('push this 0', @filename),
      PushCommand.new('push that 0', @filename),
      # ARG = SP-n-5
      LiteralHackCommand.new(<<-HACK),
        @5
        D=A
        @#{nargs}
        D=D+A      // D = n + 5
        D=-D       // D = -n-5
        @SP
        D=M+D      // D = *SP-n-5
        @ARG
        M=D        // *ARG = D
      HACK
      # LCL = SP
      LiteralHackCommand.new(<<-HACK),
        @SP
        D=M
        @LCL
        M=D
      HACK
      #GotoCommand.new(@filename,  "goto #{func}"),
      LiteralHackCommand.new(<<-HACK), # bypass the labelling of GotoCommand
        @#{func} // func name
        0;JMP
      HACK
      #LabelCommand.new(@filename, "label #{return_address}"),
      LiteralHackCommand.new(<<-HACK), # TODO: why doesn't ^ work?
        (#{return_address})
      HACK
    ].map(&:to_hack) * "\n"
  end
end

class ReturnCommand < VMCommand
  def to_hack
    [
      LiteralHackCommand.new(<<-HACK),
        // FRAME=LCL
        @LCL
        D=M
        @FRAME
        M=D

        // *ARG=pop()
        #{PopCommand.new("pop", @filename).to_hack}
        @ARG
        M=D

        // SP=ARG+1
        A=A+1
        D=A
        @SP
        M=D

        // that, this, arg, local, ret
        @FRAME
        A=A-1
        D=A
        @THAT
        M=D

        @FRAME
        A=A-1
        A=A-1
        D=A
        @THIS
        M=D

        @FRAME
        A=A-1
        A=A-1
        A=A-1
        D=A
        @ARG
        M=D

        @FRAME
        A=A-1
        A=A-1
        A=A-1
        A=A-1
        D=A
        @LCL
        M=D

        @FRAME
        A=A-1
        A=A-1
        A=A-1
        A=A-1
        A=A-1
        0;JMP
      HACK
      ## TODO prolly wrong
      #PopCommand.new("pop", @filename),
      #LiteralHackCommand.new(<<-HACK),
      #  @ARG
      #  M=D
      #HACK
      #PopCommand.new("pop", @filename),
      #LiteralHackCommand.new(<<-HACK),
      #  @SP
      #  M=D
      #HACK
      #PopCommand.new("pop that 0", @filename),
      #PopCommand.new("pop this 0", @filename),
      #PopCommand.new("pop argument 0", @filename),
      #PopCommand.new("pop local 0", @filename),
      #PopCommand.new("pop", @filename),
      #LiteralHackCommand.new(<<-HACK),
      #  A=D
      #  0;JMP
      #HACK
    ].map(&:to_hack) * "\n"
  end
end

class LiteralHackCommand
  def initialize(hack)
    @hack = hack
  end

  def to_hack
    @hack
  end
end

class BootstrapCommand < VMCommand
  def to_hack
    init_call = CallCommand.new('call Sys.init 0', @filename).to_hack
    <<-HACK
      // BOOTSTRAP
      @256
      D=A
      @SP
      M=D
      #{init_call}
      // END BOOTSTRAP
    HACK
  end
end

def main(file)
  path = file + (file.include?(?.) ? '' : '*.vm')
  files = Dir[path]
  parsers = files.map { |f| VMParser.new(f) }
  outputfile = if path.include?(?*)
      fname = path.split(?/)[-2] + '.asm'
      File.join(File.dirname(path), fname)
    else
      files[0].gsub('.vm', '.asm')
  end

  parsers[0].commands.unshift(BootstrapCommand.new('', files[0]))

  codes = parsers.map do |parser|
    parser.commands.map(&:to_hack_no_whitespace).reject(&:empty?).join("\n")
  end

  open(outputfile, 'w') do |f|
    f.puts codes.join("\n")
  end
end

main(ARGV.first)
