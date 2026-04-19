module AgentMessages
  class Sender
    class InvalidRecipient < StandardError; end
    class EmptyContent     < StandardError; end

    MAX_CONTENT_BYTES = 8_192

    def self.call(from:, to:, content:)
      new(from: from, to: to, content: content).call
    end

    def initialize(from:, to:, content:)
      @from    = from
      @to      = to
      @content = content.to_s
    end

    def call
      validate!

      AgentMessage.create!(
        from_note: @from,
        to_note:   @to,
        content:   truncated_content
      )
    end

    private

    def validate!
      raise InvalidRecipient, "from note is blank" if @from.blank?
      raise InvalidRecipient, "to note is blank"   if @to.blank?
      raise InvalidRecipient, "cannot send to self" if @from.id == @to.id
      raise EmptyContent, "content cannot be blank" if @content.strip.empty?
    end

    def truncated_content
      return @content if @content.bytesize <= MAX_CONTENT_BYTES

      head = @content.byteslice(0, MAX_CONTENT_BYTES)
      head.force_encoding(Encoding::UTF_8).scrub!
      "#{head}\n[truncated — original #{@content.bytesize} bytes]"
    end
  end
end
