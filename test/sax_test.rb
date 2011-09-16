#!/usr/bin/env ruby -wW1
# encoding: UTF-8

$: << '../lib'
$: << '../ext'

if __FILE__ == $0
  while (i = ARGV.index('-I'))
    x,path = ARGV.slice!(i, 2)
    $: << path
  end
end

require 'stringio'
require 'test/unit'
require 'optparse'
require 'ox'

opts = OptionParser.new
opts.on("-h", "--help", "Show this display")                { puts opts; Process.exit!(0) }
files = opts.parse(ARGV)

class StartSax < ::Ox::Sax
  attr_accessor :calls

  def initialize()
    @calls = []
  end

  def start_element(name, attrs)
    @calls << [:start_element, name, attrs]
  end
end

class AllSax < StartSax
  def initialize()
    super
  end

  def instruct(target, attrs)
    @calls << [:instruct, target, attrs]
  end

  def doctype(value)
    @calls << [:doctype, value]
  end

  def comment(value)
    @calls << [:comment, value]
  end

  def cdata(value)
    @calls << [:cdata, value]
  end

  def text(value)
    @calls << [:text, value]
  end

  def end_element(name)
    @calls << [:end_element, name]
  end
  
  def error(message, line, column)
    @calls << [:error, message, line, column]
  end
end

class Func < ::Test::Unit::TestCase

  def test_sax_io_pipe
    handler = AllSax.new()
    input,w = IO.pipe
    w << %{<top/>}
    w.close
    Ox.sax_parse(handler, input)
    assert_equal(handler.calls,
                 [[:start_element, 'top', nil],
                  [:end_element, 'top']])
  end

  def test_sax_io_file
    handler = AllSax.new()
    input = IO.open(IO.sysopen('basic.xml'))
    Ox.sax_parse(handler, input)
    assert_equal(handler.calls,
                 [[:start_element, 'top', nil],
                  [:end_element, 'top']])
  end

  def parse_compare(xml, expected, handler_class=AllSax)
    handler = handler_class.new()
    input = StringIO.new(xml)
    Ox.sax_parse(handler, input)
    assert_equal(expected, handler.calls)
  end
  
  def test_sax_instruct_simple
    parse_compare(%{<?xml?>}, [[:instruct, 'xml', nil]])
  end

  def test_sax_instruct_blank
    parse_compare(%{<?xml?>}, [], StartSax)
  end

  def test_sax_instruct_attrs
    parse_compare(%{<?xml version="1.0" encoding="UTF-8"?>},
                  [[:instruct, 'xml', {'version' => '1.0', 'encoding' => 'UTF-8'}]])
  end

  def test_sax_instruct_loose
    parse_compare(%{<? xml
version = "1.0"
encoding = "UTF-8" ?>},
                  [[:instruct, 'xml', {'version' => '1.0', 'encoding' => 'UTF-8'}]])
  end

  def test_sax_element_simple
    parse_compare(%{<top/>},
                  [[:start_element, 'top', nil],
                   [:end_element, 'top']])
  end

  def test_sax_element_attrs
    parse_compare(%{<top x="57" y="42"/>}, 
                  [[:start_element, 'top', {'x' => '57', 'y' => '42'}],
                   [:end_element, 'top']])
  end

  def test_sax_nested1
    parse_compare(%{<?xml version="1.0"?>
<top>
  <child>
    <grandchild/>
  </child>
</top>
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:start_element, 'child', nil],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:end_element, 'child'],
                   [:end_element, 'top'],
                  ])
  end

  def test_sax_nested1_tight
    parse_compare(%{<?xml version="1.0"?><top><child><grandchild/></child></top>},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:start_element, 'child', nil],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:end_element, 'child'],
                   [:end_element, 'top'],
                  ])
  end

  def test_sax_element_name_mismatch
    parse_compare(%{<?xml version="1.0"?><top><child><grandchild/></parent></top>},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:start_element, 'child', nil],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:error, "invalid format, element start and end names do not match", 0, 0]
                  ])
  end

  def test_sax_nested
    parse_compare(%{<?xml version="1.0"?>
<top>
  <child>
    <grandchild/>
  </child>
  <child>
    <grandchild/>
    <grandchild/>
  </child>
</top>
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:start_element, 'child', nil],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:end_element, 'child'],
                   [:start_element, 'child', nil],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:start_element, 'grandchild', nil],
                   [:end_element, 'grandchild'],
                   [:end_element, 'child'],
                   [:end_element, 'top'],
                  ])
  end
  # TBD no end element

  def test_sax_text
    parse_compare(%{<top>This is some text.</top>},
                  [[:start_element, "top", nil],
                   [:text, "This is some text."],
                   [:end_element, "top"]
                  ])
  end

  def test_sax_text_no_term
    parse_compare(%{<top>This is some text.},
                  [[:start_element, "top", nil],
                   [:error, "invalid format, text terminated unexpectedly", 0, 0],
                  ])
  end
  # TBD invalid chacters in text

  def test_sax_doctype
    parse_compare(%{<?xml version="1.0"?>
<!DOCTYPE top PUBLIC "top.dtd">
<top/>
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:doctype, ' top PUBLIC "top.dtd"'],
                   [:start_element, 'top', nil],
                   [:end_element, 'top']])
  end

    def test_sax_doctype_bad_order
    parse_compare(%{<?xml version="1.0"?>
<top/>
<!DOCTYPE top PUBLIC "top.dtd">
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:end_element, 'top'],
                   [:error, '???'],
                   [:doctype, ' top PUBLIC "top.dtd"']])
  end
  
  def test_sax_comment
    parse_compare(%{<?xml version="1.0"?>
<!--First comment.-->
<top>Before<!--Nested comment.-->After</top>
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:comment, 'First comment.'],
                   [:start_element, 'top', nil],
                   [:text, 'Before'],
                   [:comment, 'Nested comment.'],
                   [:text, 'After'],
                   [:end_element, 'top']])
  end
  # TBD non terminated comment

  def test_sax_cdata
    parse_compare(%{<?xml version="1.0"?>
<top>
  <![CDATA[This is CDATA.]]>
</top>
},
                  [[:instruct, 'xml', {'version' => '1.0'}],
                   [:start_element, 'top', nil],
                   [:cdata, 'This is CDATA.'],
                   [:end_element, 'top']])
  end
  # TBD cdata with ] in it
  # TBD non-terminated cdata
  
  # TBD mix of elements, text, and attributes - tight and loose
  # TBD read invalid xml with recoverable errors (elements out of order, multiple top elements)
  # TBD read invalid xml (missing 
  
  # TBD check line and column on errors
  # TBD test encoding

end

