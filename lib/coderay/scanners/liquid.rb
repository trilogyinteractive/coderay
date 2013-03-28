module CodeRay
module Scanners

  class Liquid < Scanner
    
    register_for :liquid
   
    DIRECTIVE_KEYWORDS = "list|endlist|for|endfor|wrap|endwrap|if|endif|unless|endunless|elsif|assign|cycle|capture|end|capture|fill|iflist|endiflist|else"

    DIRECTIVE_OPERATORS = "=|==|!=|>|<|<=|>=|contains"

    MATH = "=|==|!=|>|<|<=|>"

    FILTER_KEYWORDS = "date|capitalize|downcase|upcase|first|last|join|sort|map|size|escape_once|escape|strip_html|strip_newlines|newline_to_br|replace_first|replace|remove_first|remove|truncate|truncatewords|prepend|append|minus|plus|times|divided_by|split|modulo"

    LIQUID_DIRECTIVE_BLOCK = /
      {%
      (.*?)
      %}
    /x

    def setup
      @html_scanner = CodeRay.scanner(:html, tokens: @tokens, keep_tokens: true, keep_state: false)
    end

    def scan_spaces(encoder)
      if match = scan(/\s+/)
        encoder.text_token match, :space
      end
    end

    def scan_selector(encoder, options, match)
      scan_spaces(encoder)
      if match = scan(/in|with/)
        scan_spaces(encoder)
        encoder.text_token match, :type
        if delimiter = scan(/:/)
          encoder.text_token delimiter, :delimiter
          scan_spaces(encoder)
        end
        if variable = scan(/(\w+)|('\S+')|("\w+")/)
          encoder.text_token variable, :variable
        end
        scan_selector(encoder, options, match)
      end
    end

    def scan_directive(encoder, options, match)
      encoder.text_token match, :key
      state = :liquid
      scan_spaces(encoder)
      #This regex doesn't work and I don't know why
      if match = scan(/#{DIRECTIVE_KEYWORDS}/)
        encoder.text_token match, :directive
        scan_spaces(encoder)
        if match =~ /if/
          if match = scan(/\w+\.?\w*/)
            encoder.text_token match, :variable
          end
          scan_spaces(encoder)
          if match = scan(/#{MATH}/)
            encoder.text_token match, :char
            scan_spaces(encoder)
          end
          if match = scan(/(\w+)|('\S+')|(".+")/)
            encoder.text_token match, :variable
            scan_spaces(encoder)
          end
        end
      end
      scan_selector(encoder, options, match)
      scan_spaces(encoder)
      if match = scan(/%}/)
        encoder.text_token match, :key
        state = :initial
      end
    end

    def scan_output_filters(encoder, options, match)
      encoder.text_token match, :delimiter
      scan_spaces(encoder)
      if directive = scan(/#{FILTER_KEYWORDS}/)
        encoder.text_token directive, :directive
      end
      if delimiter = scan(/:/)
        encoder.text_token delimiter, :delimiter
      end
      scan_spaces(encoder)
      if variable = scan(/(\w+)|('\S+')|(".+")/)
        encoder.text_token variable, :variable
      end
      if next_filter = scan(/\s\|\s/)
        scan_output_filters(encoder, options, next_filter)
      end
    end

    def scan_output(encoder, options, match)
      encoder.text_token match, :key
      state = :liquid
      scan_spaces(encoder)
      if match = scan(/(\w+)|('\S+')|("\w+")/)
        encoder.text_token match, :variable
      end
      if match = scan(/(\s\|\s)/)
        scan_output_filters(encoder, options, match)   
      end
      scan_spaces(encoder)
      if match = scan(/}}/)
        encoder.text_token match, :key
      end
      state = :initial
    end

    def scan_tokens(encoder, options)
      state = :initial

      until eos?
        if (match = scan_until(/(?=({{|{%))/) || scan_rest) and not match.empty? and state != :liquid
          @html_scanner.tokenize(match, tokens: encoder)
          state = :initial
        scan_spaces(encoder)
        elsif match = scan(/{%/)
          scan_directive(encoder, options, match) 
        elsif match = scan(/{{/)
          scan_output(encoder, options, match)
        else
          raise "Else-case reached. State: #{state.to_s}."
        end
      end
      encoder
    end
  end
end
end
