require "rys"

module EasyFormDesigner
  class Engine < ::Rails::Engine
    include Rys::EngineExtensions

    rys_id "easy_form_designer"

    initializer "easy_form_designer.setup" do
      # Custom initializer
    end

  end
end
