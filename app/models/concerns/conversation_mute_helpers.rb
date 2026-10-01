module ConversationMuteHelpers
  extend ActiveSupport::Concern

  # All-or-nothing: a contact that can't be blocked must not leave the conversation resolved
  def mute!
    return unless contact

    transaction do
      resolved!
      contact.update!(blocked: true)
      create_muted_message
    end
  end

  def unmute!
    return unless contact

    transaction do
      contact.update!(blocked: false)
      create_unmuted_message
    end
  end

  def muted?
    contact&.blocked? || false
  end
end
