# name: discourse-mailgun
# about: Discourse Plugin for Mailgun webhooks
# version: 0.1
# authors: Pushpender Chaudhary
# url: https://github.com/pushpinder6805/tracks-mailgun

require 'openssl'

enabled_site_setting :discourse_base_url
enabled_site_setting :discourse_api_key
enabled_site_setting :discourse_api_username

after_initialize do
  # Make Mailgun API key visible in UI
  SiteSetting::Definition.find { |s| s.setting == :mailgun_api_key }&.tap do |s|
    s.client = true
    s.hidden = false
    s.category = 'email'
  end

  module ::DiscourseMailgun
    class Engine < ::Rails::Engine
      engine_name "discourse-mailgun"
      isolate_namespace DiscourseMailgun

      class << self
        def verify_signature(timestamp, token, signature, api_key)
          digest = OpenSSL::Digest::SHA256.new
          data = [timestamp, token].join
          hex = OpenSSL::HMAC.hexdigest(digest, api_key, data)
          signature == hex
        end

        def post(url, params)
          Excon.post(
            url,
            body: URI.encode_www_form(params),
            headers: { "Content-Type" => "application/x-www-form-urlencoded" }
          )
        end
      end
    end
  end

  require_dependency "application_controller"

  class DiscourseMailgun::MailgunController < ::ApplicationController
    before_action :verify_signature

    def incoming
      m = Mail::Message.new do
        to      params['To']
        from    params['From']
        date    params['Date']
        subject params['subject']
        body    params['body-plain']
      end

      handler_url = "#{SiteSetting.discourse_base_url}/admin/email/handle_mail"
      payload = {
        'email' => m.to_s,
        'api_key' => SiteSetting.discourse_api_key,
        'api_username' => SiteSetting.discourse_api_username
      }

      ::DiscourseMailgun::Engine.post(handler_url, payload)
      render plain: "done"
    end

    def is_api?
      true
    end

    private

    def verify_signature
      unless ::DiscourseMailgun::Engine.verify_signature(
        params['timestamp'],
        params['token'],
        params['signature'],
        SiteSetting.mailgun_api_key
      )
        render json: {}, status: :unauthorized
      end
    end
  end

  DiscourseMailgun::Engine.routes.draw do
    post "/incoming" => "mailgun#incoming"
  end

  Discourse::Application.routes.append do
    mount ::DiscourseMailgun::Engine, at: "/mailgun"
  end
end
