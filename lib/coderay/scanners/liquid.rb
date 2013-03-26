module CodeRay
module Scanners

  class Liquid < Scanner
    
    register_for :liquid
   
    DIRECTIVE_KEYWORDS = "endlist|list|endfor|for|endwrap|wrap|endif|if|endunless|unless|elsif|assignlist|assign|cycle|capture|end|capture|fill|endiflist|iflist|else"

    DIRECTIVE_OPERATORS = "=|==|!=|>|<|<=|>=|contains|\+"

    MATH = /==|=|!=|>|<=|<|>|\+/

    FILTER_KEYWORDS = "date|capitalize|downcase|upcase|first|last|join|sort|map|size|escape_once|escape|strip_html|strip_newlines|newline_to_br|replace_first|replace|remove_first|remove|truncate|truncatewords|prepend|append|minus|plus|times|divided_by|split|modulo"

    LIQUID_DIRECTIVE_BLOCK = /
      {{1,2}%
      (.*?)
      %}{1,2}
    /x

    def setup
      @html_scanner = CodeRay.scanner(:html, tokens: @tokens, keep_tokens: true, keep_state: true)
    end

    def scan_spaces(encoder)
      if match = scan(/\s+/)
        encoder.text_token match, :space
      end
    end

    def scan_selector(encoder, options, match)
      scan_spaces(encoder)
      if match = scan(/in|with|script|tabs|items_per_tab/)
        Rails.logger.debug 'DEBUG: Scanning selector'
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
      else
        false
      end
    end

    def scan_directive(encoder, options, match)
      Rails.logger.debug 'DEBUG: Scanning directive'
      encoder.text_token match, :tag
      state = :liquid
      scan_spaces(encoder)
      #This regex doesn't work and I don't know why
      if match = scan(/#{DIRECTIVE_KEYWORDS}/)
        encoder.text_token match, :directive
        scan_spaces(encoder)
        if match =~ /if|assign|assignlist/
          if match = scan(/\w+\.?\w*/)
            encoder.text_token match, :variable
          end
          scan_spaces(encoder)
          if match = scan(/#{MATH}/)
            encoder.text_token match, :operator
            scan_spaces(encoder)
            scan_selector(encoder, options, match)
          end
          if match = scan(/(\w+)|('\S+')|(".+")/)
            encoder.text_token match, :variable
            scan_spaces(encoder)
          end
        end
      end
      scan_selector(encoder, options, match)
      scan_spaces(encoder)
      if match = scan(/%}{1,2}/)
        encoder.text_token match, :tag
        state = :initial
      end
    end

    def scan_output_filters(encoder, options, match)
      encoder.text_token match, :operator
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
      Rails.logger.debug 'DEBUG: Scanning output'
      encoder.text_token match, :tag
      state = :liquid
      scan_spaces(encoder)
      if match = scan(/(\w+\.?\w*)|('\S+')|("\w+")/)
        encoder.text_token match, :variable
      end
      if match = scan(/(\s\|\s)/)
        scan_output_filters(encoder, options, match)   
      end
      scan_spaces(encoder)
      if match = scan(/}{2,3}/)
        encoder.text_token match, :tag
      end
      state = :initial
    end

    def scan_tokens(encoder, options)
      Rails.logger.debug "DEBUG: Scan started: #{self.string}"
      state = :initial

      until eos?
        if (match = scan_until(/(?=({{2,3}|{{1,2}%))/) || scan_rest) and not match.empty? and state != :liquid
          Rails.logger.debug "DEBUG: HTML scanning: #{match}"
          if match =~ /^"|^'/
            @html_scanner.tokenize(match, { tokens: encoder, state: :attribute_value_string })
          else
            @html_scanner.tokenize(match, tokens: encoder)
          end
          state = :initial
        scan_spaces(encoder)
        elsif match = scan(/{{1,2}%/)
          scan_directive(encoder, options, match) 
        elsif match = scan(/{{2,3}/)
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
