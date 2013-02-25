# Copyright (c) 2012 The Mirah project authors. All Rights Reserved.
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

package org.mirah.jvm.mirrors

import java.util.Collections
import java.util.HashSet
import java.util.LinkedList
import java.util.List
import java.util.logging.Logger
import java.util.logging.Level
import org.mirah.MirahLogFormatter
import org.mirah.typer.ResolvedType
import org.mirah.jvm.types.JVMType
import org.mirah.jvm.types.JVMMethod

class MethodLookup
  def self.initialize:void
    @@log = Logger.getLogger(MethodLookup.class.getName)
  end

  class << self
    def isSubType(subtype:ResolvedType, supertype:ResolvedType):boolean
      return true if subtype == supertype
      if subtype.kind_of?(JVMType) && supertype.kind_of?(JVMType)
        return isJvmSubType(JVMType(subtype), JVMType(supertype))
      end
      return true if subtype.matchesAnything
      return supertype.matchesAnything
    end
  
    def isJvmSubType(subtype:JVMType, supertype:JVMType):boolean
      if subtype.isPrimitive
        return supertype.isPrimitive && isPrimitiveSubType(subtype, supertype)
      end
      super_desc = supertype.class_id
      explored = HashSet.new
      to_explore = LinkedList.new
      to_explore.add(subtype)
      until to_explore.isEmpty
        next_type = to_explore.removeFirst
        descriptor = next_type.class_id
        return true if descriptor.equals(super_desc)
        unless explored.contains(descriptor)
          explored.add(descriptor)
          to_explore.add(next_type.superclass) if next_type.superclass
          next_type.interfaces.each {|i| to_explore.add(JVMType(i.resolve))}
        end
      end
      return false
    end
  
    def isPrimitiveSubType(subtype:JVMType, supertype:JVMType):boolean
      sub_desc = subtype.class_id.charAt(0)
      super_desc = supertype.class_id.charAt(0)
      order = "BSIJFD"
      if sub_desc == super_desc
        return true
      elsif sub_desc == ?Z
        return false
      elsif sub_desc == ?C
        return order.indexOf(super_desc) > 1
      else
        return order.indexOf(super_desc) >= order.indexOf(sub_desc)
      end
    end

    # Returns 0, 1, -1 or NaN if a & b are the same type,
    # a < b, a > b, or neither is a subtype.
    def subtypeComparison(a:JVMType, b:JVMType):double
      return 0.0 if a.class_id.equals(b.class_id)
      if isJvmSubType(b, a)
        return -1.0
      elsif isJvmSubType(a, b)
        return 1.0
      else
        return Double.NaN
      end
    end

    # Returns the most specific method if one exists, or the maximally
    # specific methods if the given methods are ambiguous.
    # Implements the rules in JLS 2nd edition, 15.12.2.2.
    # Notably, it does not support varargs or generic methods.
    def findMaximallySpecific(methods:List):List
      maximal = LinkedList.new
      ambiguous = false
      methods.each do |m|
        method = JVMMethod(m)
        
        # Compare 'method' with each of the maximally specific methods.
        # If it is strictly more specific than all of them, it is the
        # new most specific method.
        # If any maximally specific method is strictly more specefic than
        # 'method', it is not maximally specific.
        most_specific = true
        more_specific = true
        method_ambiguous = false
        maximal.each do |x|
          item = JVMMethod(x)
          comparison = compareSpecificity(method, item)
          @@log.finest("compareSpecificity('#{method}', '#{item}') = #{comparison}")
          if comparison < 0
            more_specific = false
            most_specific = false
            break
          elsif comparison == 0
            most_specific = false
          elsif Double.isNaN(comparison)
            most_specific = false
            method_ambiguous = true
          end
        end
        if most_specific
          maximal.clear()
          maximal.add(method)
          ambiguous = false
        elsif more_specific
          maximal.add(method)
          ambiguous = true if method_ambiguous
        end
      end
      if maximal.size > 1 && !ambiguous
        return Collections.singletonList(pickMostSpecific(maximal))
      end
      maximal
    end

    # Returns:
    #  -  < 0 if b is strictly more specific than a, including the target
    #  -  > 0 if a is strictly more specific than b, including the target
    #  -  0 if both are more specific (same override, ignoring the target)
    #  - NaN if neither is more specific (arguments are ambiguous, ignoring the target)
    # Note that methods with the same signature but from unrelated classes return 0.
    # This should only happen when at least one of the methods comes from an interface,
    # so pickMostSpecific will break the tie.
    def compareSpecificity(a:JVMMethod, b:JVMMethod):double
      raise IllegalArgumentException if a.argumentTypes.size != b.argumentTypes.size
      comparison = 0.0
      a.argumentTypes.size.times do |i|
        a_arg = JVMType(a.argumentTypes.get(i))
        b_arg = JVMType(b.argumentTypes.get(i))
        arg_comparison = subtypeComparison(a_arg, b_arg)
        return arg_comparison if Double.isNaN(arg_comparison)
        if arg_comparison != 0.0
          if comparison == 0.0
            comparison = arg_comparison
          elsif comparison != arg_comparison
            return Double.NaN
          end
        end
      end
      target_comparison = subtypeComparison(a.declaringClass, b.declaringClass)
      if comparison == target_comparison || target_comparison == 0.0
        return comparison
      elsif comparison == 0.0
        if Double.isNaN(target_comparison)
          # Return equal so pickMostSpecific gets to decide
          return comparison
        else
          return target_comparison
        end
      else
        return Double.NaN
      end
    end

    # Breaks specificity ties according the the JLS 2nd edition rules:
    #   'methods' must be a list of JVMMethods with the same signature.
    #   If one is not abstract it is returned, otherwise one is arbitrarily chosen.
    def pickMostSpecific(methods:List):JVMMethod
      method = nil
      methods.each do |m|
        method = JVMMethod(m)
        return method unless method.isAbstract
      end
      method
    end

    def main(args:String[]):void
      logger = MirahLogFormatter.new(true).install
      @@log.setLevel(Level.ALL)
      types = MirrorTypeSystem.new
      methods = LinkedList.new
      args.each do |arg|
        methods.add(FakeMember.create(types, arg))
      end
      puts findMaximallySpecific(methods)
    end
  end
end