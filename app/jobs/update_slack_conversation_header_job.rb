class UpdateSlackConversationHeaderJob < MutexApplicationJob
  queue_as :medium
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  def perform(conversation, hook)
    # Same mutex as SendOnSlackJob, so an update can't race the header being posted
    key = format(::Redis::Alfred::SLACK_MESSAGE_MUTEX, conversation_id: conversation.id, reference_id: hook.reference_id)
    with_lock(key) do
      Integrations::Slack::UpdateConversationHeaderService.new(conversation: conversation.reload, hook: hook).perform
    end
  end
end
