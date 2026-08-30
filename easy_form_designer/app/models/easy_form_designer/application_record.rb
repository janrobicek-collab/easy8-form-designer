module EasyFormDesigner
  class ApplicationRecord < ApplicationRecord
    include Redmine::SafeAttributes

    self.table_name_prefix = "easy_form_designer_"
    self.abstract_class = true

  end
end
