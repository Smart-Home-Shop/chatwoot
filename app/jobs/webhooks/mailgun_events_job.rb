class Webhooks::MailgunEventsJob < ApplicationJob
  queue_as :low

  def perform(event)
    status = status_for(event)
    return if status.blank?

    # Outgoing email replies keep the Message-ID Chatwoot generated as their source_id
    message = Message.where(message_type: %i[outgoing template]).find_by(source_id: event.dig('message', 'headers', 'message-id'))
    return if message.blank?

    Messages::StatusUpdateService.new(message, status, status == 'failed' ? external_error(event) : nil).perform
  end

  private

  def status_for(event)
    case event['event']
    when 'delivered' then 'delivered'
    when 'opened' then 'read'
    when 'failed' then 'failed' if event['severity'] == 'permanent'
    end
  end

  def external_error(event)
    delivery_status = event['delivery-status']
    "#{event['recipient']}: #{delivery_status['code']} #{delivery_status['message'].presence || delivery_status['description']}"
  end
end
