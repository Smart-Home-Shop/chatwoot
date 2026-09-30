class Api::V1::Accounts::Conversations::SpamsController < Api::V1::Accounts::Conversations::BaseController
  LABEL = 'spam'.freeze
  LABEL_COLOR = '#FF0000'.freeze

  # Labels the conversation as spam and blocks the contact in one step, creating the account label if needed
  def create
    ActiveRecord::Base.transaction do
      Current.account.labels.find_or_create_by!(title: LABEL) do |label|
        label.color = LABEL_COLOR
        label.show_on_sidebar = true
      end
      @conversation.add_labels([LABEL])
      @conversation.mute!
    end
    render json: { payload: @conversation.label_list }
  end
end
