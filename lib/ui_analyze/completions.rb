# frozen_string_literal: true

module UiAnalyze
  module Completions
    SHELLS = %w[bash zsh fish].freeze

    def self.generate(shell)
      case shell
      when "bash" then bash
      when "zsh"  then zsh
      when "fish" then fish
      else
        warn "Error: unknown shell '#{shell}' (supported: #{SHELLS.join(", ")})"
        exit 1
      end
    end

    def self.bash
      <<~'BASH'
        _ui_analyze() {
          local cur prev words
          _init_completion || return
          cur="${COMP_WORDS[COMP_CWORD]}"
          prev="${COMP_WORDS[COMP_CWORD-1]}"

          case "$prev" in
            --from|--to)
              COMPREPLY=($(compgen -W "$(date +%Y-%m-%d)" -- "$cur"))
              return ;;
            --completions)
              COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
              return ;;
          esac

          case "$cur" in
            -*)
              COMPREPLY=($(compgen -W "--from --to --anon --anonymize --completions --help" -- "$cur"))
              return ;;
          esac

          # Default: complete paths (directories and .tar.gz files)
          local IFS=$'\n'
          COMPREPLY=($(compgen -f -- "$cur" | grep -E '(/$|\.tar\.gz$)'))
          compopt -o nospace 2>/dev/null
        }
        complete -F _ui_analyze ui-analyze
      BASH
    end

    def self.zsh
      <<~'ZSH'
        #compdef ui-analyze

        _ui_analyze() {
          local -a opts
          opts=(
            '--from[Only show boots on or after DATE]:date (YYYY-MM-DD):'
            '--to[Only show boots on or before DATE]:date (YYYY-MM-DD):'
            '--anon[Replace identifying values with placeholders]'
            '--anonymize[Replace identifying values with placeholders]'
            '--completions[Print shell completion script]:shell:(bash zsh fish)'
            '--help[Show help]'
          )

          _arguments -s \
            $opts \
            '*:support dump (directory or .tar.gz):_files -g "*(/) *.tar.gz"'
        }

        _ui_analyze "$@"
      ZSH
    end

    def self.fish
      <<~'FISH'
        # ui-analyze fish completions

        # Disable file completions by default; we add our own below
        complete -c ui-analyze -f

        complete -c ui-analyze -l from        -d 'Only show boots on or after DATE (YYYY-MM-DD)' -x
        complete -c ui-analyze -l to          -d 'Only show boots on or before DATE (YYYY-MM-DD)' -x
        complete -c ui-analyze -l anon        -d 'Replace identifying values with placeholders'
        complete -c ui-analyze -l anonymize   -d 'Replace identifying values with placeholders'
        complete -c ui-analyze -l completions -d 'Print shell completion script' -x -a 'bash zsh fish'
        complete -c ui-analyze -l help        -d 'Show help'

        # Re-enable path completions for the dump argument (dirs and .tar.gz)
        complete -c ui-analyze -F -a '(__fish_complete_path)'
      FISH
    end
  end
end
