module Duby::AST
  class Arguments < Node
    attr_accessor :args, :opt_args, :rest_arg, :block_arg
    
    def initialize(parent, line_number, &block)
      super(parent, line_number, &block)
      @args, @opt_args, @rest_arg, @block_arg = children
    end
    
    def infer(typer)
      unless @inferred_type
        @inferred_type = args ? args.map {|arg| typer.infer(arg)} : []
      end
    end
  end
      
  class Argument < Node
    include Typed
  end
      
  class RequiredArgument < Argument
    include Named
    include Scoped
    
    def initialize(parent, line_number, name)
      super(parent, line_number)

      @name = name
    end
    
    def infer(typer)
      unless @inferred_type
        # if not already typed, check parent of parent (MethodDefinition) for signature info
        method_def = parent.parent
        signature = method_def.signature

        # if signature, search for this argument
        if signature[name.intern]
          @inferred_type = typer.learn_local_type(scope, name, signature[name.intern])
        else
          @inferred_type = typer.local_type(scope, name)
        end
          
        unless @inferred_type
          typer.defer(self)
        end
      end
        
      @inferred_type
    end
  end
      
  class OptionalArgument < Argument
    include Named
    include Scoped
    attr_accessor :child
    
    def initialize(parent, line_number, &block)
      super(parent, line_number, &block)
      @child = children[0]
      @name = @child.name
    end
  end
      
  class RestArgument < Argument
    include Named
    include Scoped
    
    def initialize(parent, line_number, name)
      super(parent, line_number)

      @name = name
    end
  end
      
  class BlockArgument < Argument
    include Named
    
    def initialize(parent, line_number, name)
      super(parent, line_number)

      @name = name
    end
  end
      
  class MethodDefinition < Node
    include Named
    include Scope
    attr_accessor :signature, :arguments, :body, :defining_class
        
    def initialize(parent, line_number, name, &block)
      super(parent, line_number, &block)
      @signature, @arguments, @body = children
      @name = name
    end
    
    def infer(typer)
      @defining_class ||= typer.self_type
      typer.infer_signature(self)
      typer.infer(arguments)
      forced_type = signature[:return]
      inferred_type = body ? typer.infer(body) : typer.no_type
        
      if !inferred_type
        typer.defer(self)
      else
        actual_type = if forced_type.nil?
          inferred_type
        else
          forced_type
        end
        if actual_type.unreachable?
          actual_type = typer.no_type
        end
        
        if !abstract? &&
            forced_type != typer.no_type &&
            !actual_type.is_parent(inferred_type)
          raise Duby::Typer::InferenceError.new(
              "Inferred return type %s is incompatible with declared %s" %
              [inferred_type, actual_type], self)
        end

        @inferred_type = typer.learn_method_type(defining_class, name, arguments.inferred_type, actual_type, signature[:throws])
        signature[:return] = @inferred_type
      end
        
      @inferred_type
    end
    
    def abstract?
      node = parent
      while node && !node.kind_of?(Scope)
        node = node.parent
      end
      InterfaceDeclaration === node
    end
    
    def static?
      false
    end
  end
      
  class StaticMethodDefinition < MethodDefinition
    def defining_class
      @defining_class.meta
    end
    
    def static?
      true
    end
  end
  
  class ConstructorDefinition < MethodDefinition
    attr_accessor :super_args, :this_args
    
    def initialize(*args)
      super
      extract_delegate_constructor
    end
    
    def first_node
      if @body.kind_of? Body
        @body.children[0]
      else
        @body
      end
    end
    
    def first_node=(new_node)
      if @body.kind_of? Body
        @body.children[0] = new_node
      else
        @body = children[2] = new_node
      end
    end
    
    def extract_delegate_constructor
      # TODO verify that this constructor exists during type inference.
      possible_delegate = first_node
      if FunctionalCall === possible_delegate &&
          possible_delegate.name == 'initialize'
        @this_args = possible_delegate.parameters
        self.first_node = Noop.new(self, position)
      end
    end
    
    def infer(typer)
      unless @inferred_type
        this_args.each {|a| typer.infer(a)} if this_args
        super_args.each {|a| typer.infer(a)} if super_args
      end
      super
    end
  end
end