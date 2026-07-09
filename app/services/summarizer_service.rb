# frozen_string_literal: true

class SummarizerService
  MAX_INPUT_LENGTH = 8_000

  def initialize(text)
    @text = text.to_s[0, MAX_INPUT_LENGTH]
  end

  def call
    return nil if @text.blank?

    client = Aws::BedrockRuntime::Client.new(
      region: ENV.fetch("AWS_REGION", "us-east-1"),
      retry_limit: 3,
      retry_backoff: ->(context) { sleep(2**context.retries) }
    )

    response = client.converse(
      model_id: ENV.fetch("BEDROCK_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0"),
      messages: [
        {
          role: "user",
          content: [{ text: prompt }]
        }
      ],
      inference_config: {
        max_tokens: 1024,
        temperature: 0.3
      }
    )

    response.output.message.content[0].text
  rescue Aws::BedrockRuntime::Errors::ServiceError => e
    Rails.logger.error("Bedrock API error: #{e.class} - #{e.message}")
    nil
  end

  private

  def prompt
    <<~PROMPT
      以下のWebページの内容を日本語で200〜400文字程度に要約してください。
      要点を箇条書きではなく、自然な文章でまとめてください。
      英語の内容であっても、必ず日本語で要約を作成してください。

      ---
      #{@text}
    PROMPT
  end
end
