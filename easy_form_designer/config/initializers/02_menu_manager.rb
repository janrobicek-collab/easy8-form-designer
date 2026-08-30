EasyInitHelper.register_menu_block do
  Redmine::MenuManager.map :top_menu do |menu|
    menu.push :easy_form_designer,
              :easy_form_designer_forms_path,
              caption: :"easy_form_designer.top_menu_link",
              html: { class: "icon icon-list",
                      category: :core_features, },
              if: proc { EasyFormDesigner.visible_for?(User.current) }
  end
end
