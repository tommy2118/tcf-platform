# frozen_string_literal: true

module TcfPlatform
  # Security management for configuration and secrets
  class SecurityManager
    SECRET_PATTERNS = [
      /password/i,
      /secret/i,
      /token/i,
      /key/i,
      /api[_-]?key/i,
      /auth/i,
      /credential/i
    ].freeze

    MASK_CHAR = '*'
    UNMASK_PREFIX_LENGTH = 4
    UNMASK_SUFFIX_LENGTH = 4

    class << self
      def mask_sensitive_data(data)
        case data
        when Hash
          mask_hash(data)
        when String
          mask_string_if_sensitive(data)
        when Array
          data.map { |item| mask_sensitive_data(item) }
        else
          data
        end
      end

      def detect_secrets(text)
        secrets = []

        SECRET_PATTERNS.each do |pattern|
          text.scan(pattern) do |match|
            secrets << {
              pattern: pattern,
              match: match,
              position: Regexp.last_match.offset(0)
            }
          end
        end

        secrets
      end

      def validate_secret_strength(secret)
        return { valid: false, reasons: ['Secret cannot be empty'] } if secret.nil? || secret.empty?

        reasons = []
        reasons << 'Secret too short (minimum 16 characters)' if secret.length < 16
        reasons << 'Secret should contain numbers' unless secret.match?(/\d/)
        reasons << 'Secret should contain lowercase letters' unless secret.match?(/[a-z]/)
        reasons << 'Secret should contain uppercase letters' unless secret.match?(/[A-Z]/)
        reasons << 'Secret should contain special characters' unless secret.match?(/[^a-zA-Z0-9]/)
        reasons << 'Secret appears to be a common password' if common_password?(secret)

        {
          valid: reasons.empty?,
          reasons: reasons,
          strength: calculate_strength(secret)
        }
      end

      def generate_secure_secret(length = 32)
        chars = [
          ('a'..'z').to_a,
          ('A'..'Z').to_a,
          ('0'..'9').to_a,
          %w[! @ # $ % ^ & * - _ + = [ ] { } | : ; < > ? . ,]
        ].flatten

        Array.new(length) { chars.sample }.join
      end

      def audit_environment_secrets
        findings = []

        ENV.each do |key, value|
          next unless value

          next unless appears_sensitive?(key)

          validation = validate_secret_strength(value)

          next if validation[:valid]

          findings << {
            variable: key,
            issues: validation[:reasons],
            strength: validation[:strength],
            severity: determine_severity(validation[:strength])
          }
        end

        findings
      end

      def secure_compare(a, b)
        return false unless a.bytesize == b.bytesize

        l = a.unpack('C*')
        res = 0
        b.each_byte { |byte| res |= byte ^ l.shift }
        res.zero?
      end

      private

      def mask_hash(hash)
        masked = {}

        hash.each do |key, value|
          masked[key] = if appears_sensitive?(key.to_s)
                          mask_value(value.to_s)
                        else
                          mask_sensitive_data(value)
                        end
        end

        masked
      end

      def mask_string_if_sensitive(string)
        # Check if the string looks like it contains sensitive data
        SECRET_PATTERNS.any? { |pattern| string.match?(pattern) } ? mask_value(string) : string
      end

      def appears_sensitive?(key)
        SECRET_PATTERNS.any? { |pattern| key.match?(pattern) }
      end

      def mask_value(value)
        return value if value.length <= (UNMASK_PREFIX_LENGTH + UNMASK_SUFFIX_LENGTH)

        prefix = value[0...UNMASK_PREFIX_LENGTH]
        suffix = value[-UNMASK_SUFFIX_LENGTH..]
        middle_length = value.length - UNMASK_PREFIX_LENGTH - UNMASK_SUFFIX_LENGTH

        "#{prefix}#{MASK_CHAR * middle_length}#{suffix}"
      end

      def common_password?(secret)
        common_passwords = %w[
          password
          123456
          password123
          admin
          qwerty
          letmein
          welcome
          monkey
          dragon
          secret
          default
          changeme
          root
          toor
          pass
          test
          guest
        ]

        common_passwords.any? { |pwd| secret.downcase.include?(pwd) }
      end

      def calculate_strength(secret)
        score = 0

        # Length scoring
        score += 1 if secret.length >= 8
        score += 1 if secret.length >= 12
        score += 1 if secret.length >= 16
        score += 1 if secret.length >= 20

        # Character variety scoring
        score += 1 if secret.match?(/[a-z]/)
        score += 1 if secret.match?(/[A-Z]/)
        score += 1 if secret.match?(/\d/)
        score += 1 if secret.match?(/[^a-zA-Z0-9]/)

        # Complexity scoring
        score += 1 if secret.match?(/[a-z].*[A-Z]|[A-Z].*[a-z]/)
        score += 1 if secret.match?(/\d.*[a-zA-Z]|[a-zA-Z].*\d/)

        # Penalty for common patterns
        score -= 2 if common_password?(secret)
        score -= 1 if secret.match?(/(.)\1{2,}/) # Repeated characters
        score -= 1 if secret.match?(/(012|123|234|345|456|567|678|789|890|abc|bcd|cde)/)

        score = 0 if score.negative?

        case score
        when 0..3
          :very_weak
        when 4..5
          :weak
        when 6..7
          :medium
        when 8..9
          :strong
        else
          :very_strong
        end
      end

      def determine_severity(strength)
        case strength
        when :very_weak, :weak
          :critical
        when :medium
          :high
        when :strong
          :medium
        else
          :low
        end
      end
    end
  end
end
