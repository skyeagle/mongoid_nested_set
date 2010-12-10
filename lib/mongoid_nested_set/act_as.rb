module Mongoid::Acts::NestedSet

  module ActAs

    # Configuration options are:
    #
    # * +:parent_field+ - field name to use for keeping the parent id (default: parent_id)
    # * +:left_field+ - field name for left boundary data, default 'lft'
    # * +:right_field+ - field name for right boundary data, default 'rgt'
    # * +:scope+ - restricts what is to be considered a list.  Given a symbol, it'll attach
    #   "_id" (if it hasn't been already) and use that as the foreign key restriction.  You
    #   can also pass an array to scope by multiple attributes
    # * +:dependent+ - behavior for cascading destroy.  If set to :destroy, all the child
    #   objects are destroyed alongside this object by calling their destroy method.  If set
    #   to :delete_all (default), all the child objects are deleted without calling their
    #   destroy method.
    #
    # See Mongoid::Acts::NestedSet::ClassMethods for a list of class methods and
    # Mongoid::Acts::NestedSet::InstanceMethods for a list of instance methods added to
    # acts_as_nested_set models
    def acts_as_nested_set(options = {})
      options = {
        :parent_field => 'parent_id',
        :left_field => 'lft',
        :right_field => 'rgt',
        :dependent => :delete_all, # or :destroy
      }.merge(options)

      if options[:scope].is_a?(Symbol) && options[:scope].to_s !~ /_id$/
        options[:scope] = "#{options[:scope]}_id".intern
      end

      class_attribute :acts_as_nested_set_options, :instance_writer => false
      self.acts_as_nested_set_options = options

      unless self.is_a?(Base::ClassMethods)
        include Comparable
        include Fields
        include Base::InstanceMethods

        extend Fields
        extend Base::ClassMethods

        field left_field_name, :type => Integer
        field right_field_name, :type => Integer
        field :depth, :type => Integer

        references_many :children, :class_name => self.name, :foreign_key => parent_field_name, :inverse_of => :parent
        referenced_in   :parent,   :class_name => self.name, :foreign_key => parent_field_name

        attr_accessor :skip_before_destroy

        if accessible_attributes.blank?
          attr_protected left_field_name.intern, right_field_name.intern
        end

        before_create  :set_default_left_and_right
        before_save    :store_new_parent
        after_save     :move_to_new_parent
        before_destroy :destroy_descendants

        # no assignment to structure fields
        [left_field_name, right_field_name].each do |field|
          module_eval <<-"end_eval", __FILE__, __LINE__
                  def #{field}=(x)
                    raise NameError, "Unauthorized assignment to #{field}: it's an internal field handled by acts_as_nested_set code, use move_to_* methods instead.", "#{field}"
                  end
          end_eval
        end

        scope :roots, lambda {
          where(parent_field_name => nil).asc(left_field_name)
        }
        scope :leaves, lambda {
          where("this.#{quoted_right_field_name} - this.#{quoted_left_field_name} == 1").asc(left_field_name)
        }
        scope :with_depth, lambda { |level|
          where(:depth => level).asc(left_field_name)
        }

        define_callbacks :move, :terminator => "result == false"
      end
    end
  end

end