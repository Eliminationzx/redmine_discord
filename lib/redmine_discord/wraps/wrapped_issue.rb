require_relative '../embed_objects/embed_field'

module RedmineDiscord
  class Wraps::WrappedIssue
    MAX_DESCRIPTION_LENGTH = 1000  # Prevents exceeding Discord's field limit
    MAX_DIFF_LENGTH = 1000         # Limit diff size for large changes

    def initialize(issue)
      @issue = issue
    end

    def to_heading_title
      "#{@issue.project.name} - #{@issue.tracker} ##{@issue.id}: #{@issue.subject}"
    end

    def to_description_field
      return nil unless @issue.description.present?

      truncated_description = truncate_text(@issue.description, MAX_DESCRIPTION_LENGTH)
      formatted_description = "```#{truncated_description.gsub(/`/, "\u200b`")}```"

      EmbedObjects::EmbedField.new('Description', formatted_description, false).to_hash
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

        value = if attribute_name == 'parent_id'
                  value.blank? ? nil : "[##{value.id}](#{url_of value.id})"
                else
                  value.blank? ? nil : "`#{value}`"
                end

        EmbedObjects::EmbedField.new(attribute_name, value, true).to_hash if value
      end
    end

    def to_diff_fields
      @issue.attributes.keys.map { |key| get_diff_field_for(key) }.compact
    end

    private

    def get_diff_field_for(attribute_name)
      new_value = value_for(attribute_name)
      old_value = old_value_for(attribute_name)
      attribute_root_name = attribute_name.chomp('_id')

      return nil if new_value == old_value # No change, skip diff

      case attribute_root_name
      when 'Description'
        new_value = @issue.description.to_s.strip
        old_value = @issue.description_was.to_s.strip

        return nil if new_value == old_value # No change in description

        description_diff = format_diff(old_value, new_value, MAX_DIFF_LENGTH)
        EmbedObjects::EmbedField.new(attribute_root_name, description_diff, false).to_hash
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
      text.length > max_length ? "#{text[0...max_length]}..." : text
    end

    def format_diff(old_text, new_text, max_length)
      diff = "```diff\n- #{old_text}\n+ #{new_text}\n```"
      truncate_text(diff, max_length)
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

      return @issue.send("#{attribute_name}_was") if attribute_root_name == attribute_name

      if attribute_root_name == 'assigned_to'
        return User.find(@issue.assigned_to_id_was) rescue nil
      end

      return @issue.send("#{attribute_root_name}_was") if @issue.respond_to?("#{attribute_root_name}_was")

      old_id = @issue.send("#{attribute_root_name}_id_was")

      case attribute_root_name
      when 'project'
        Project.find(old_id)
      when 'category'
        IssueCategory.find(old_id)
      when 'priority'
        IssuePriority.find(old_id)
      when 'fixed_version'
        Version.find(old_id)
      when 'parent'
        Issue.find(old_id)
      when 'author'
        @issue.author
      when 'root'
        @issue.root_id
      else
        puts "Unknown attribute name given: #{attribute_root_name}"
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
