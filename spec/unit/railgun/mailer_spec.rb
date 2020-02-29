require 'json'
require 'logger'
require 'spec_helper'
require 'mailgun'
require 'railgun'

ActionMailer::Base.raise_delivery_errors = true
ActionMailer::Base.delivery_method = :test
Rails.logger = Logger.new('/dev/null')
Rails.logger.level = Logger::DEBUG

class UnitTestMailer < ActionMailer::Base
  default from: 'unittest@example.org'

  def plain_message(address, subject, headers)
    headers(headers)
    mail(to: address, subject: subject) do |format|
      format.text { render plain: "Test!" }
      format.html { render html: "<p>Test!</p>".html_safe }
    end
  end

  def message_with_attachment(address, subject)
    attachments['info.txt'] = {
      :content => File.read('docs/railgun/Overview.md'),
      :mime_type => 'text/plain',
    }
    mail(to: address, subject: subject) do |format|
      format.text { render plain: "Test!" }
      format.html { render html: "<p>Test!</p>".html_safe }
    end
  end

end

describe 'Railgun::Mailer' do

  it 'has a mailgun_client property which returns a Mailgun::Client' do
    config = {
      api_key:  {},
      domain:   {}
    }
    @mailer_obj = Railgun::Mailer.new(config)

    expect(@mailer_obj.mailgun_client).to be_a(Mailgun::Client)
  end

  it 'properly creates a message body' do
    message = UnitTestMailer.plain_message('test@example.org', 'Test!', {})
    body = Railgun.transform_for_mailgun(message)

    expect(body).to include(:message)
    expect(body).to include(:to)

    expect(body[:to]).to eq(['test@example.org'])
  end

  it 'adds options to message body' do
    message = UnitTestMailer.plain_message('test@example.org', '', {})
    message.mailgun_options ||= {
      'tracking-opens' => 'true',
    }

    body = Railgun.transform_for_mailgun(message)

    expect(body).to include('o:tracking-opens')
    expect(body['o:tracking-opens']).to eq('true')
  end

  it 'adds variables to message body' do
    message = UnitTestMailer.plain_message('test@example.org', '', {})
    message.mailgun_variables ||= {
      'user' => {:id => '1', :name => 'tstark'},
    }

    body = Railgun.transform_for_mailgun(message)

    expect(body).to include('v:user')

    var_body = JSON.load(body['v:user'])
    expect(var_body).to include('id')
    expect(var_body).to include('name')
    expect(var_body['id']).to eq('1')
    expect(var_body['name']).to eq('tstark')
  end

  it 'adds headers to message body' do
    message = UnitTestMailer.plain_message('test@example.org', '', {})
    message.mailgun_headers ||= {
      'x-unit-test' => 'true',
    }

    body = Railgun.transform_for_mailgun(message)

    expect(body[:message]).to include('x-unit-test')
  end

  it 'adds headers to message body from mailer' do
    message = UnitTestMailer.plain_message('test@example.org', '', {
      'x-unit-test-2' => 'true',
    })

    body = Railgun.transform_for_mailgun(message)

    expect(body[:message]).to include('x-unit-test-2')
  end

  it 'properly handles To, Bcc, and CC headers' do
    message = UnitTestMailer.plain_message('test@example.org', 'Test!', {
      # `To` is set on the envelope, so it should be ignored as a header
      'To' => 'user@example.com',
      # If `Bcc` or `Cc` are set as headers, they should be carried over as POST params, not headers
      'Bcc' => ['list@example.org'],
      'Cc' => ['admin@example.com'],
    })

    body = Railgun.transform_for_mailgun(message)

    expect(body[:to]).to contain_exactly('test@example.org', 'list@example.org', 'admin@example.com')
  end

  it 'delivers!' do
    message = UnitTestMailer.plain_message('test@example.org', '', {})
    message.deliver_now

    expect(ActionMailer::Base.deliveries).to include(message)
  end
end
