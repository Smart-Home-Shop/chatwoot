class Captain::SpamTriageService < Captain::BaseTaskService
  VERDICTS = %w[spam legit uncertain].freeze
  BODY_LIMIT = 4000

  pattr_initialize [:account!, :message!]

  def perform
    response = make_api_call(
      feature: 'spam_triage',
      messages: [
        { role: 'system', content: system_prompt },
        { role: 'user', content: message_details }
      ]
    )
    return response if response[:error]

    parse_verdict(response[:message])
  end

  private

  def system_prompt
    Liquid::Template.parse(prompt_from_file('spam_triage')).render('business_name' => account.name)
  end

  def message_details
    email = message.content_attributes&.dig('email') || {}
    sender = message.sender
    <<~DETAILS
      Channel: #{message.inbox.channel_type.demodulize}
      From: #{sender&.name} <#{sender.try(:email) || sender.try(:phone_number)}>
      Subject: #{email['subject'] || message.conversation.additional_attributes&.dig('mail_subject')}

      #{message.content.to_s.first(BODY_LIMIT)}
    DETAILS
  end

  def parse_verdict(content)
    raw = content.to_s.strip
    parsed = JSON.parse(raw.match(/```json\s*(.*?)\s*```/m)&.captures&.first || raw)
    return { error: 'Invalid LLM response format' } unless VERDICTS.include?(parsed['verdict'])

    { verdict: parsed['verdict'], confidence: parsed['confidence'].to_f.clamp(0, 1), reason: parsed['reason'].to_s }
  rescue JSON::ParserError
    { error: 'Invalid LLM response format' }
  end

  def event_name
    'spam_triage'
  end
end
