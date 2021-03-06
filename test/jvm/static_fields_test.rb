# Copyright (c) 2015 The Mirah project authors. All Rights Reserved.
# All contributing project authors may be found in the NOTICE file.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
require 'test_helper'

class StaticFieldsTest < Test::Unit::TestCase
  def test_static_field_inheritance_lookup_with_dot
    cls, = compile(<<-EOF)
      import java.util.GregorianCalendar
      puts GregorianCalendar.AM
    EOF

    assert_run_output("0\n", cls)
  end

  def test_static_field_inheritance_lookup_with_double_colon
    cls, = compile(<<-EOF)
      import java.util.GregorianCalendar
      puts GregorianCalendar::AM
    EOF

    assert_run_output("0\n", cls)
  end

  def test_create_constant
    cls, = compile(<<-EOF)
      CONSTANT = 1
      puts CONSTANT
    EOF
    assert_run_output("1\n", cls)
  end

  def test_constant_public
    cls, = compile(<<-EOF)
      class Bar
        CONSTANT = 1
      end

      puts Bar::CONSTANT
    EOF
    assert_run_output("1\n", cls)
  end
  
  def test_static_final_constant
    cls, = compile(<<-EOF)
      class Bar
      
        static_final :serialVersionUID, -1234567890123456789
        
        class << self
          def reflect
            field = Bar.class.getDeclaredField("serialVersionUID")
            puts field.getModifiers
            puts field.get(nil)
          end
        end
      end
      
      Bar.reflect
    EOF
    assert_run_output("26\n-1234567890123456789\n", cls)
  end
  
  def test_transient
    cls, = compile(%q[
      class Bar implements java::io::Serializable
      
        static_final :serialVersionUID, -1234567890123456789
        
        transient :b
        
        def initialize(a:int,b:int)
          @a = a
          @b = b
        end
        
        def toString
          "Bar(#{@a},#{@b})"
        end
      end
      
      bout = java::io::ByteArrayOutputStream.new
      oout = java::io::ObjectOutputStream.new(bout)
      oout.writeObject(Bar.new(5,7))
      oout.close
      bin  = java::io::ObjectInputStream.new(java::io::ByteArrayInputStream.new(bout.toByteArray))
      puts Bar(bin.readObject)
    ])
    assert_run_output("Bar(5,0)\n", cls) # b=7 should be forgotten, because b is a transient field. 
  end
  
  def test_local_variable_in_constant_assignment
    cls, = compile(<<-EOF)
      CONSTANT1 = begin
        a = 5
        b = a+3
        b
      end
      class Bar
        CONSTANT2 = [5,8,7].map do |x|
          x-1
        end # implicit variable use generated by #map() macro 
        def self.print_C2
          puts CONSTANT2.join(",")
        end
      end
      puts CONSTANT1
      Bar.print_C2
    EOF
   assert_run_output("8\n4,7,6\n", cls)
  end
  def test_declare_constant_in_instance_method_is_an_error
    e = assert_raise_kind_of Mirah::MirahError do
      cls, = compile(<<-EOF)
        class Foo
          def foo
            CONSTANT = 1
            puts CONSTANT
          end
        end
        
        Foo.new.foo
      EOF
      assert_run_output("1\n", cls)
    end
  end  
  def test_constants_are_public_and_final_and_static
    cls, = compile(<<-EOF)
      class Foo
        CONSTANT = 1
      end
      
      puts Foo.class.getDeclaredField('CONSTANT').getModifiers
    EOF
    assert_run_output("#{java.lang.reflect.Modifier::PUBLIC | java.lang.reflect.Modifier::FINAL | java.lang.reflect.Modifier::STATIC}\n", cls)
  end
  def test_constants_can_be_accessed_across_class_boundaries
    cls, = compile(<<-EOF)
      class Foo
        CONSTANT = 42
      end
      
      puts Foo.CONSTANT
    EOF
    assert_run_output("42\n", cls)
  end
  def test_on_static_init_macro
    cls, = compile(<<-EOF)
      interface SomeMacros
        macro def self.on_static_init(block:Block)
          ClassInitializer.new(block.position,[block.body])
        end
      end
      
      class Foo
        implements SomeMacros
        
        class << self
          attr_accessor bar:int
        end
        
        on_static_init do
          self.bar = 42
        end
      end
      
      puts Foo.bar
    EOF
    assert_run_output("42\n", cls)
  end
end
