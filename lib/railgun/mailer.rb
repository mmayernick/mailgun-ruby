require 'action_mailer'
require 'json'
require 'mailgun'
require 'rails'
require 'railgun/errors'

module Railgun

  # Railgun::Mailer is an ActionMailer provider for sending mail through
  # Mailgun.
  class Mailer

    # [Hash] config ->
    #   Requires *at least* `api_key` and `domain` keys.
    attr_accessor :config, :domain, :settings

    # Initialize the Railgun mailer.
    #
    # @param [Hash] config Hash of config values, typically from `app_config.action_mailer.mailgun_config`
    def initialize(config)
      @config = config

      [:api_key, :domain].each do |k|
        raise Railgun::ConfigurationError.new("Config requires `#{k}` key", @config) unless @config.has_key?(k)
      end

      @mg_client = Mailgun::Client.new(
        config[:api_key],
        config[:api_host] || 'api.mailgun.net',
        config[:api_version] || 'v3',
        config[:api_ssl].nil? ? true : config[:api_ssl],
      )
      @domain = @config[:domain]

      # To avoid exception in mail gem v2.6
      @settings = { return_response: true }

      if (@config[:fake_message_send] || false)
        Rails.logger.info "NOTE: fake message sending has been enabled for mailgun-ruby!"
        @mg_client.enable_test_mode!
      end
    end

    def deliver!(mail)
      mg_message = Railgun.transform_for_mailgun(mail)
      response = @mg_client.send_message(@domain, mg_message)

      if response.code == 200 then
        mg_id = response.to_h['id']
        mail.message_id = mg_id
      end
      response
    end

    def mailgun_client
      @mg_client
    end

  end

  module_function

  # Performs a series of transformations on the `mailgun*` attributes.
  # After prefixing them with the proper option type, they are added to
  # the message hash where they will then be sent to the API as JSON.
  #
  # It is important to note that headers set in `mailgun_headers` on the message
  # WILL overwrite headers set via `mail.headers()`.
  #
  # @param [Mail::Message] mail message to transform
  #
  # @return [Hash] transformed message hash
  def transform_for_mailgun(mail)
    mail.headers(mail.mailgun_headers || {})
    message = build_message_object(mail)

    # v:* attributes (variables)
    mail.mailgun_variables.try(:each) do |k, v|
      message["v:#{k}"] = JSON.dump(v)
    end

    # o:* attributes (options)
    mail.mailgun_options.try(:each) do |k, v|
      message["o:#{k}"] = v
    end

    # reject blank values
    message.delete_if do |k, v|
      return true if v.nil?

      # if it's an array remove empty elements
      v.delete_if { |i| i.respond_to?(:empty?) && i.empty? } if v.is_a?(Array)

      v.respond_to?(:empty?) && v.empty?
    end

    return message
  end

  # Acts on a Rails/ActionMailer message object and uses Mailgun::MessageBuilder
  # to construct a new message.
  #
  # @param [Mail::Message] mail message to transform
  #
  # @returns [Hash] Message hash from Mailgun::MessageBuilder
  def build_message_object(mail)
    message = {
      message: mail.encoded,
      to: []
    }

    [:to, :cc, :bcc].each do |rcpt_type|
      addrs = mail[rcpt_type] || nil
      case addrs
      when String
        # Likely a single recipient
        message[:to] << addrs
      when Array
        addrs.each do |addr|
          message[:to] << addr
        end
      when Mail::Field
        message[:to] << addrs.to_s
      end
    end

    message
  end

end
