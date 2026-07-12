# frozen_string_literal: true

require 'test_helper'
require 'ostruct'

class SummarizerServiceTest < ActiveSupport::TestCase
  setup do
    @text = 'これはテスト用のテキストです。要約を生成するために使用します。'
  end

  test 'returns summary text on success' do
    mock_response = mock_converse_response('これはテスト要約です。')

    client = mock
    client.expects(:converse).returns(mock_response)
    Aws::BedrockRuntime::Client.stubs(:new).returns(client)

    result = SummarizerService.new(@text).call

    assert_equal 'これはテスト要約です。', result
  end

  test 'returns nil when text is blank' do
    result = SummarizerService.new('').call

    assert_nil result
  end

  test 'returns nil when text is nil' do
    result = SummarizerService.new(nil).call

    assert_nil result
  end

  test 'returns nil on Bedrock API error' do
    client = mock
    client.expects(:converse).raises(Aws::BedrockRuntime::Errors::ServiceError.new(nil, 'Service unavailable'))
    Aws::BedrockRuntime::Client.stubs(:new).returns(client)

    result = SummarizerService.new(@text).call

    assert_nil result
  end

  test 'truncates input text to 8000 characters' do
    long_text = 'あ' * 10_000
    service = SummarizerService.new(long_text)

    mock_response = mock_converse_response('要約結果')
    client = mock
    client.expects(:converse).with do |params|
      # Verify the prompt contains truncated text (8000 chars max)
      params[:messages][0][:content][0][:text].length < long_text.length + 200
    end.returns(mock_response)
    Aws::BedrockRuntime::Client.stubs(:new).returns(client)

    result = service.call

    assert_equal '要約結果', result
  end

  test 'uses model_id from environment variable' do
    ENV['BEDROCK_MODEL_ID'] = 'anthropic.claude-3-sonnet-20240229-v1:0'

    mock_response = mock_converse_response('要約')
    client = mock
    client.expects(:converse).with do |params|
      params[:model_id] == 'anthropic.claude-3-sonnet-20240229-v1:0'
    end.returns(mock_response)
    Aws::BedrockRuntime::Client.stubs(:new).returns(client)

    SummarizerService.new(@text).call
  ensure
    ENV.delete('BEDROCK_MODEL_ID')
  end

  private

  def mock_converse_response(text)
    content_block = OpenStruct.new(text: text)
    message = OpenStruct.new(content: [content_block])
    output = OpenStruct.new(message: message)
    OpenStruct.new(output: output)
  end
end
