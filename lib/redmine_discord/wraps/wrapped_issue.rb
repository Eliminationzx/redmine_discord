require_relative '../embed_objects/issue_embeds'

module RedmineDiscord
  class WrappedIssue
    def initialize(issue)
      @issue = issue
    end

    def to_author_field
      EmbedField.new('Author', "#{@issue.author.firstname} #{@issue.author.lastname}", true).to_hash
    end

    def to_assignee_field
      if @issue.assigned_to.present?
        EmbedField.new('Assignee',
                       "#{@issue.assigned_to.firstname} #{@issue.assigned_to.lastname}",
                       true).to_hash
      end
    end

    def to_due_date_field
      if @issue.due_date
        EmbedField.new('Due Date', @issue.due_date.to_s, true).to_hash
      end
    end

    def to_estimated_hours_field
      if @issue.estimated_hours
        EmbedField.new('Estimated Hours', @issue.estimated_hours.to_s, true).to_hash
      end
    end

    def to_priority_field
      EmbedField.new('Priority', @issue.priority.name, true).to_hash
    end

    def to_heading_title
      "#{@issue.project.name} - #{@issue.tracker} ##{@issue.id}: #{@issue.subject}"
    end

    def to_description_field
      if @issue.description.present?
        EmbedField.new('Description', @issue.description, false).to_hash
      end
    end

    def resolve_absolute_url
      host = Setting.host_name.to_s.chomp('/')
      protocol = Setting.protocol

      "#{protocol}://#{host}/issues/#{@issue.id}"
    end

    def get_separator_field
      EmbedField.new('---------------------------', "\u200b", false).to_hash
    end

    def to_diff_fields
      diff_fields = @issue.attributes.keys.map {|attrib_key|
        # treat description field specially because this gets handled another time
        get_diff_field_for attrib_key unless attrib_key == 'description'
      }.compact

      # TODO add diff field of description(just like diff command)

      diff_fields
    end

    private

    def get_diff_field_for(attribute_name)
      attribute_root_name = attribute_name.chomp('_id')

      new_value, old_value =
        if attribute_name == attribute_root_name
          [@issue.send(attribute_name), @issue.send(attribute_name + '_was')]
        else
          diff_for_id_attribute attribute_root_name
        end

      EmbedField.new(attribute_root_name,
                     "`#{new_value || 'None'}` => `#{old_value || 'None'}`",
                     true).to_hash unless new_value == old_value
    end

    def diff_for_id_attribute(attribute_root_name)
      if Issue.method_defined? "#{attribute_root_name}_was".to_sym
        return [@issue.send(attribute_root_name), @issue.send(attribute_root_name + '_was')]
      end

      new_value = @issue.send(attribute_root_name)
      old_id = @issue.send(attribute_root_name + '_id_was')

      old_value = case attribute_root_name
        when 'project'
          Project.find(old_id)
        when 'category'
          nil
        when 'priority'
          IssuePriority.find(old_id)
        when 'fixed_version'
          nil
        when 'author'
          # ignore this because it never changes
          @issue.author
        when 'parent'
          nil
        when 'root'
          # ignore this attribute because this can be inferred from tracker/subject
          @issue.root
        else
          puts "unknown attribute name given : #{attribute_root_name}"
          nil
      end

      [new_value, old_value]
    end
  end
end
