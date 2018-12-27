#     ____      ____
#    / __/___  / __/
#   / /_/_  / / /_
#  / __/ / /_/ __/
# /_/   /___/_/-completion.bash
#
# - $FZF_TMUX               (default: 0)
# - $FZF_TMUX_HEIGHT        (default: '40%')
# - $FZF_COMPLETION_TRIGGER (default: '**')
# - $FZF_COMPLETION_OPTS    (default: empty)

################################################################################
# lukelbd edits: summary
# * Goal is to set completion trigger to '' (always on), bind tab key to 'cancel', and
#   use the completion option 'maxdepth 1' -- this enables us to succissively toggle
#   completion on and off with tab, and lets us fuzzy search the depth-1 directory contents.
# * To make this more similar to bash completion, have modified __fzf_generic_path_completion
#   to *test* whether an entry is a directory or file. If it is a directory, we append it with
#   a slash (and no space, like in _fzf_dir_completion). If it is a file, we append it with
#   zero space. That way if you select a directory, you can immediately press tab again
#   to search *this* directory. This can be *critical* for huge directory trees (e.g. $HOME).
# * Inicidentally this means a complete command invoking __fzf_generic_path_completion
#   must *always* be called with the option -o nospace -- spaces are added dynamically if the
#   item is not a directory.
################################################################################

# Function for parsing new command-line option -- list of files to ignore
# For example, .DS_Store
_fzf_ignore() {
  if [ -z "$1" ]; then
    echo -false # -not -false == -true
  else
    echo -name $(echo "$1" | xargs | sed 's/ / -o -name /g')
  fi
}
# Similar idea here
_fzf_include() {
  if [ -z "$1" ]; then
    echo -true
  else
    echo -name $(echo "$1" | xargs | sed 's/ / -o -name /g')
  fi
}

# To use custom commands instead of find, override _fzf_compgen_{path,dir}
# They accept one argument -- the base directory
# Below prunes results in git directories, enforces some user variables,
# prunes input directory itself from find result, and remove leading './'
# if ! declare -f _fzf_compgen_path > /dev/null; then
_fzf_compgen_path() {
  command find -L "$1" \
    $FZF_COMPLETION_FIND_OPTS \
    -name .git -prune -o -name .svn -prune -o \( -type d -o -type f -o -type l \) \
    -a -not \( $(_fzf_ignore $FZF_COMPLETION_FIND_IGNORE) \) \
    -a \( $(_fzf_include $FZF_COMPLETION_FIND_INCLUDE) \) \
    -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
}
# fi

# if ! declare -f _fzf_compgen_dir > /dev/null; then
_fzf_compgen_dir() {
  command find -L "$1" \
    $FZF_COMPLETION_FIND_OPTS \
    -name .git -prune -o -name .svn -prune -o -type d \
    -a -not \( $(_fzf_ignore $FZF_COMPLETION_FIND_IGNORE) \) \
    -a \( $(_fzf_include $FZF_COMPLETION_FIND_INCLUDE) \) \
    -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
}
# fi

###########################################################

# To redraw line after fzf closes (printf '\e[5n')
bind '"\e[0n": redraw-current-line'

__fzfcmd_complete() {
  [ -n "$TMUX_PANE" ] && [ "${FZF_TMUX:-0}" != 0 ] && [ ${LINES:-40} -gt 15 ] &&
    echo "fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}" || echo "fzf"
}

__fzf_orig_completion_filter() {
  # Records _fzf_orig_completion_<command>="complete <opts> -F function #<command>"
  # Also if has a 'nospace' option, and not already in the string, add to __fzf_nospace_commands string
  sed 's/^\(.*-F\) *\([^ ]*\).* \([^ ]*\)$/export _fzf_orig_completion_\3="\1 %s \3 #\2"; [[ "\1" = *" -o nospace "* ]] \&\& [[ ! "$__fzf_nospace_commands" = *" \3 "* ]] \&\& __fzf_nospace_commands="$__fzf_nospace_commands \3 ";/' |
  awk -F= '{OFS = FS} {gsub(/[^A-Za-z0-9_= ;]/, "_", $1);}1'
}

_fzf_opts_completion() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  opts="
    -x --extended
    -e --exact
    --algo
    -i +i
    -n --nth
    --with-nth
    -d --delimiter
    +s --no-sort
    --tac
    --tiebreak
    -m --multi
    --no-mouse
    --bind
    --cycle
    --no-hscroll
    --jump-labels
    --height
    --literal
    --reverse
    --margin
    --inline-info
    --prompt
    --header
    --header-lines
    --ansi
    --tabstop
    --color
    --no-bold
    --history
    --history-size
    --preview
    --preview-window
    -q --query
    -1 --select-1
    -0 --exit-0
    -f --filter
    --print-query
    --expect
    --sync"

  case "${prev}" in
  --tiebreak)
    COMPREPLY=( $(compgen -W "length begin end index" -- "$cur") )
    return 0
    ;;
  --color)
    COMPREPLY=( $(compgen -W "dark light 16 bw" -- "$cur") )
    return 0
    ;;
  --history)
    COMPREPLY=()
    return 0
    ;;
  esac

  if [[ "$cur" =~ ^-|\+ ]]; then
    COMPREPLY=( $(compgen -W "${opts}" -- "$cur") )
    return 0
  fi

  return 0
}

_fzf_handle_dynamic_completion() {
  local cmd orig_var orig ret orig_cmd orig_complete
  cmd="$1"
  shift
  orig_cmd="$1"
  orig_var="_fzf_orig_completion_$cmd"
  orig="${!orig_var##*#}" # trim comment
  if [ -n "$orig" ] && type "$orig" > /dev/null 2>&1; then
    $orig "$@" # call completion command
  elif [ -n "$_fzf_completion_loader" ]; then
    orig_complete=$(complete -p "$cmd" 2> /dev/null)
    _completion_loader "$@"
    ret=$?
    # _completion_loader may not have updated completion for the command
    if [ "$(complete -p "$cmd" 2> /dev/null)" != "$orig_complete" ]; then
      eval "$(complete | command grep " -F.* $orig_cmd$" | __fzf_orig_completion_filter)"
      if [[ "$__fzf_nospace_commands" = *" $orig_cmd "* ]]; then
        eval "${orig_complete/ -F / -o nospace -F }"
      else
        eval "$orig_complete"
      fi
    fi
    return $ret
  fi
}

# lukelbd: Now takes just two arguments -- the compgen command, and fzf options
__fzf_generic_path_completion() {
  local cur base dir leftover matches trigger cmd fzf opts end varcomp generator
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  COMPREPLY=()
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  cur="${COMP_WORDS[COMP_CWORD]}" # cmd line word under cursor
  # lukelbd: Complete paths and variables
  varcomp=false
  [[ "$cur" == '$'* ]] && varcomp=true
  if [[ "$cur" == *"$trigger" ]]; then
    base=${cur:0:${#cur}-${#trigger}}
    eval "base=$base"
    [[ $base = *"/"* ]] && dir="$base"
    while true; do
      if [ -z "$dir" ] || [ -d "$dir" ]; then
        # lukelbd: Changed functionality here: make suffix dependent on whether
        # or not the item is a directory -- if so, slash, if not, space
        leftover=${base/#"$dir"}
        leftover=${leftover/#\/}
        [ -z "$dir" ] && dir='.'
        count=0
        if $varcomp; then # variable completion
          generator="compgen -v"
          leftover="${cur:1}"
          opts="+m" # one at a time!
        else
          generator="$1 $(printf %q "$dir")"
          opts="$2"
        fi
        matches=$(eval "$generator" | tr -s '/' | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $opts -q "$leftover" | while read -r item; do
          let count+=1
          if [ -d "$item" ]; then printf "%q/" "$item" | tr -s '/'
          else printf "%q " "$item"
          fi
          done)
        $varcomp && matches="${matches%% *}" # trim spaces!
        # lukelbd: If the command (i.e. word on first line of shell) is a
        # nospace command, add space.... what? This must be a bug, right?
        # [[ "$__fzf_nospace_commands" = *" ${COMP_WORDS[0]} "* ]] && matches="$matches "
        if [ -n "$matches" ]; then
          if $varcomp; then
            COMPREPLY=( "${!matches}" )
          else
            COMPREPLY=( "$matches" )
          fi
        else
          COMPREPLY=( "$cur" )
        fi
        printf '\e[5n' # redraws terminal line
        return 0
      fi
      dir=$(dirname "$dir")
      [[ "$dir" =~ /$ ]] || dir="$dir"/
    done
  # lukelbd: Trigger not active, defer to default completion
  else
    shift
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

_fzf_complete() {
  local cur selected trigger cmd fzf post
  post="$(caller 0 | awk '{print $2}')_post"   # the filename, with a _post suffix
  type -t "$post" > /dev/null 2>&1 || post=cat # empty
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ "$cur" == *"$trigger" ]]; then
    cur=${cur:0:${#cur}-${#trigger}}
    selected=$(cat | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $1 -q "$cur" | $post | tr '\n' ' ')
    selected=${selected% } # Strip trailing space not to repeat "-o nospace"
    printf '\e[5n'
    if [ -n "$selected" ]; then
      COMPREPLY=( "$selected" )
      return 0
    fi
  else
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

# lukelbd: Now argument 3 does nothing; suffix determined by test
# Just receive 'name' of completion generator function which calls a find command
# NOTE: The arg 2 '-' are additional fzf command line opts; '-m' means enable
# multi select (not a big deal if enabled when usually not necessary).
_fzf_path_completion() {
  __fzf_generic_path_completion _fzf_compgen_path "-m" "$@"
}

# lukelbd: Deprecated. No file only completion.
_fzf_file_completion() {
  _fzf_path_completion "$@"
}

# lukelbd: Deprecaed. No dir only completion.
_fzf_dir_completion() {
  __fzf_generic_path_completion _fzf_compgen_dir "" "$@"
}

###########################################################
# lukelbd: 'Special' overrides included with fzf

_fzf_complete_kill() {
  [ -n "${COMP_WORDS[COMP_CWORD]}" ] && return 1

  local selected fzf
  fzf="$(__fzfcmd_complete)"
  selected=$(command ps -ef | sed 1d | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-50%} --min-height 15 --reverse $FZF_DEFAULT_OPTS --preview 'echo {}' --preview-window down:3:wrap $FZF_COMPLETION_OPTS" $fzf -m | awk '{print $2}' | tr '\n' ' ')
  printf '\e[5n'

  if [ -n "$selected" ]; then
    COMPREPLY=( "$selected" )
    return 0
  fi
}

_fzf_complete_telnet() {
  _fzf_complete '+m' "$@" < <(
    command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0' |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

_fzf_complete_ssh() {
  _fzf_complete '+m' "$@" < <(
    cat <(cat ~/.ssh/config /etc/ssh/ssh_config 2> /dev/null | command grep -i '^host ' | command grep -v '[*?]' | awk '{for (i = 2; i <= NF; i++) print $1 " " $i}') \
        <(command grep -oE '^[[a-z0-9.,:-]+' ~/.ssh/known_hosts | tr ',' '\n' | tr -d '[' | awk '{ print $1 " " $1 }') \
        <(command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0') |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

_fzf_complete_unset() {
  _fzf_complete '-m' "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_complete_export() {
  _fzf_complete '-m' "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_complete_unalias() {
  _fzf_complete '-m' "$@" < <(
    alias | sed 's/=.*//' | sed 's/.* //'
  )
}

# fzf options
complete -o default -F _fzf_opts_completion fzf

###########################################################
# lukelbd: Custom 'special' overrides

_fzf_special="shopt help man type which bind alias unalias function git cdo"
for _command in $_fzf_special; do
  # Generating function for special commands
  # _find="find . -maxdepth 1 -mindepth 1 | sed 's:^\\./::'"
  case $_command in
    shopt)
      _generator="shopt | cut -d' ' -f1 | cut -d$'\\t' -f1" ;;
    help|man|type|which)
      _generator="cat \$HOME/.commands | grep -v '[!.:]'" ;; # faster than loading every time
    unalias|alias)
      _generator="compgen -a" ;;
    bind)
      _generator="bind -l" ;;
    function)
      _generator="compgen -A function" ;;
    git)
      _generator="cat <(_fzf_compgen_path .) <(git commands | sed 's/$/ (command)/g' | column -t)" ;;
    cdo)
      _generator="cat <(_fzf_compgen_path .) <(cdo --operators | sed 's:[ ]*[^ ]*$::g' | sed 's/^\\([^ ]*[ ]*\\)\\(.*\\)$/\\1(\\2) /g' | tr '[:upper:]' '[:lower:]') <(find . -depth 1 | sed 's:^\\./::') " ;;
  esac

  # Post-processing commands *must* have name <name_of_complete_function>_post
  # Note for some commands, probably want to list both *subcommands* and *files*
  case $_command in
    git|cdo) eval "_fzf_complete_${_command}_post() {
      cat /dev/stdin | cut -d' ' -f1
    }" ;;
  esac

  # Create functions, and declare completions
  eval "_fzf_complete_$_command() {
        _fzf_complete '+m' \"\$@\" < <( $_generator )
        }"
  complete -F _fzf_complete_$_command $_command
done


# Path completion with file extension filter
# For info see: https://unix.stackexchange.com/a/15309/112647
_fzf_find_prefix='-name .git -prune -o -name .svn -prune -o ( -type d -o -type f -o -type l )'
for _command in pdf image html; do
  case $_command in
    image) _filter="\\( -iname \\*.jpg -o -iname \\*.png -o -iname \\*.gif -o -iname \\*.svg -o -iname \\*.eps -o -iname \\*.pdf \\)" ;;
    html)  _filter="-iname \\*.html" ;;
    pdf)   _filter="-name \\*.pdf" ;;
  esac
  eval "_fzf_compgen_$_command() {
    command find -L \"\$1\" \
      \$FZF_COMPLETION_FIND_OPTS \
      -name .git -prune -o -name .svn -prune -o \\( -type d -o -type f -o -type l \\) \
      -a $_filter -a -not -path \"\$1\" -print 2> /dev/null | sed 's@^\\./@@'
  }"
  eval "_fzf_complete_$_command() {
        __fzf_generic_path_completion _fzf_compgen_$_command \"-m\" \"\$@\"
        }"
  complete -o nospace -F _fzf_complete_$_command $_command
done

# lukelbd: a_cmds is deprecated, just use complete -D path completion by default
a_cmds="${FZF_COMPLETION_FILE_COMMANDS:-awk cat diff diff3 emacs emacsclient ex file ftp g++ gcc gvim head hg java javac ld less more mvim nvim patch perl python ruby sed sftp sort source tail tee uniq vi view vim wc xdg-open basename bunzip2 bzip2 chmod chown curl cp dirname du find git grep gunzip gzip hg jar ln ls mv open rm rsync scp svn tar unzip zip}"
x_cmds="${FZF_COMPLETION_PID_COMMANDS:-kill ssh telnet unset unalias export}"
d_cmds="${FZF_COMPLETION_DIR_COMMANDS:-cd pushd rmdir}" # fill with right three

###########################################################
# lukelbd: Declare complete commands

# Preserve existing completion
eval "$(complete |
  sed -E '/-F/!d; / _fzf/d; '"/ ($(echo $a_cmds $x_cmds $d_cmds | sed 's/ /|/g; s/+/\\+/g'))$/"'!d' |
  __fzf_orig_completion_filter)"

# Dunno what this does
if type _completion_loader > /dev/null 2>&1; then
  _fzf_completion_loader=1
fi

# Helper function
_fzf_defc() {
  local cmd func opts orig_var orig def
  cmd="$1"
  func="$2"
  opts="$3"
  orig_var="_fzf_orig_completion_${cmd//[^A-Za-z0-9_]/_}"
  orig="${!orig_var}" # expands to *value* of variable named ${orig_var}
  if [ -n "$orig" ]; then
    printf -v def "$orig" "$func" # assign to shell variable def
    eval "$def"                   # add function to existing completion command
  else
    complete -F "$func" $opts "$cmd"
  fi
}

# Default completion; now use the -D flag instead of enumerating commands
# Trying to get completion to work for all environment variables, just whenever
# you start a word with dollar sign.
complete -D -F _fzf_path_completion -o nospace -o default -o bashdefault # ideal, but this seems to break stuff
for cmd in $d_cmds; do
  _fzf_defc "$cmd" _fzf_dir_completion "-o nospace -o dirnames"
done
# _fzf_defc "$cmd" _fzf_path_completion "-o default -o bashdefault" # original a_cmds loop

# Remove helper
unset _fzf_defc

# Kill completion
complete -F _fzf_complete_kill -o nospace -o default -o bashdefault kill

# Host completion
complete -F _fzf_complete_ssh -o default -o bashdefault ssh
complete -F _fzf_complete_telnet -o default -o bashdefault telnet

# Environment variables / Aliases
complete -F _fzf_complete_unset -o default -o bashdefault unset
complete -F _fzf_complete_export -o default -o bashdefault export
complete -F _fzf_complete_unalias -o default -o bashdefault unalias

unset cmd d_cmds a_cmds x_cmds
