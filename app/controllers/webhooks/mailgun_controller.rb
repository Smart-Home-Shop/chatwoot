class Webhooks::MailgunController < ActionController::API
  def events
    return head :unauthorized unless authenticated?

    Webhooks::MailgunEventsJob.perform_later(params.require('event-data').to_unsafe_h)
    head :ok
  end

  private

  # Mailgun signs webhooks with the same key it uses for inbound routes
  def authenticated?
    signature = params.require(:signature)
    ActionMailbox::Ingresses::Mailgun::InboundEmailsController::Authenticator.new(
      key: ENV.fetch('MAILGUN_INGRESS_SIGNING_KEY'),
      timestamp: signature.require(:timestamp),
      token: signature.require(:token),
      signature: signature.require(:signature)
    ).authenticated?
  end
end
