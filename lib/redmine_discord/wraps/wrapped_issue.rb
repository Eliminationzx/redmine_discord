require_relative '../embed_objects/embed_field'

module RedmineDiscord
  class Wraps::WrappedIssue
    DESCRIPTION_LIMIT = 1000
    DIFF_LIMIT = 1000

    def initialize(issue)
      @issue = issue
    end

    def to_heading_title
      "#{@issue.project.name} - #{@issue.tracker} ##{@issue.id}: #{@issue.subject}"
    end

    def to_description_field
      return unless @issue.description.present?

      truncated_description = truncate_text(@issue.description, DESCRIPTION_LIMIT)
      description = "```#{truncated_description.gsub(/`/, "\u200b`")}```"

      EmbedObjects::EmbedField.new('Description', description, false).to_hash
    end

    def resolve_absolute_url
      url_of @issue.id
    end

    def to_creation_information_fields
      display_attributes = ['author_id', 'assigned_to_id', 'priority_id', 'due_date',
                            'status_id', 'done_ratio', 'estimated_hours',
                            'category_id', 'fixed_version_id', 'parent_id']

      display_attributes.map do |attribute_name|
        value = value_for(attribute_name) rescue nil

        next if value.blank?

        value = attribute_name == 'parent_id' ? "[##{value.id}](#{url_of(value.id)})" : "`#{value}`"
        EmbedObjects::EmbedField.new(attribute_name, value, true).to_hash
      end.compact
    end

    def to_diff_fields
      @issue.attributes.keys.map { |key| get_diff_field_for(key) }.compact
    end

    private

    def get_diff_field_for(attribute_name)
      new_value = value_for(attribute_name)
      old_value = old_value_for(attribute_name)

      attribute_root_name = attribute_name.chomp('_id')

      return nil if new_value == old_value

      case attribute_root_name
      when 'description'
        new_value = @issue.description.to_s.strip
        old_value = @issue.description_was.to_s.strip

        if new_value != old_value
          description_diff = "```diff\n- #{truncate_text(old_value, DIFF_LIMIT / 2)}\n+ #{truncate_text(new_value, DIFF_LIMIT / 2)}```"
          EmbedObjects::EmbedField.new(attribute_root_name, description_diff, false).to_hash
        end
      when 'parent'
        new_value, old_value = [new_value, old_value].map do |issue|
          issue.blank? ? '`N/A`' : "[##{issue.id}](#{url_of(issue.id)})"
        end
        EmbedObjects::EmbedField.new(attribute_root_name, "#{old_value} => #{new_value}", true).to_hash
      else
        embed_value = "`#{old_value || 'N/A'}` => `#{new_value || 'N/A'}`"
        EmbedObjects::EmbedField.new(attribute_root_name, embed_value, true).to_hash
      end
    end

    def truncate_text(text, max_length)
      return text if text.length <= max_length

      "#{text[0, max_length]} [...]"
    end

    def value_for(attribute_name)
      if attribute_name == 'root_id'
        @issue.root_id
      elsif attribute_name == 'parent_id'
        Issue.find(@issue.parent_issue_id)
      else
        @issue.send attribute_name.chomp('_id')
      end rescue nil
    end

    def old_value_for(attribute_name)
      attribute_root_name = attribute_name.chomp('_id')

      return @issue.send(attribute_name + '_was') if attribute_root_name == attribute_name

      return User.find(@issue.assigned_to_id_was) if attribute_root_name == 'assigned_to'

      return @issue.send(attribute_root_name + '_was') if @issue.respond_to?("#{attribute_root_name}_was")

      old_id = @issue.send("#{attribute_root_name}_id_was")

      case attribute_root_name
      when 'project' then Project.find(old_id)
      when 'category' then IssueCategory.find(old_id)
      when 'priority' then IssuePriority.find(old_id)
      when 'fixed_version' then Version.find(old_id)
      when 'parent' then Issue.find(old_id)
      when 'author' then @issue.author
      when 'root' then @issue.root_id
      else
        puts "unknown attribute name given: #{attribute_root_name}"
        @issue.send(attribute_root_name)
      end rescue nil
    end

    def url_of(issue_id)
      host = Setting.host_name.to_s.chomp('/')
      protocol = Setting.protocol

      "#{protocol}://#{host}/issues/#{issue_id}"
    end
  end
end
