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
#
if [[ $- =~ i ]]; then

################################################################################
# lukelbd edits
# * Goal is to set completion trigger to '' (always on), bind tab key to
#   'cancel', and use the completion option 'maxdepth 1' -- this enables us
#   to succissively toggle completion on and off with tab, and lets us fuzzy
#   search the depth-1 directory contents.
# * To make this more similar to bash completion, have modified
#   __fzf_generic_path_completion to *test* whether an entry is a directory
#   or file. If it is a directory, we append it with a slash (and no space,
#   like in _fzf_dir_completion). If it is a file, we append it with zero
#   space. That way if you select a directory, you can immediately press tab
#   again to search *this* directory. This can be *critical* for huge
#   directory trees (e.g. $HOME). Inicidentally this means a complete command invoking
#   __fzf_generic_path_completion must *always* be called with the option
#   -o nospace -- spaces are added dynamically if the item is not a directory.
################################################################################
# General functions, helper functions
################################################################################
# Generic path completion commands that prune leading './'
_fzf_compgen_path() {
  if [ -n "$FZF_COMPGEN_PATH_COMMAND" ]; then
    eval "$FZF_COMPGEN_PATH_COMMAND"
  else
    command find -L "$1" \
      -maxdepth 1 -mindepth 1 \
      -name .git -prune -o -name .svn -prune -o \( -type d -o -type f -o -type l \) \
      -print 2>/dev/null | sed 's@^.*/@@'
  fi
}
_fzf_compgen_dir() {
  if [ -n "$FZF_COMPGEN_DIR_COMMAND" ]; then
    eval "$FZF_COMPGEN_DIR_COMMAND"
  else
    command find -L "$1" \
      -maxdepth 1 -mindepth 1 \
      -name .git -prune -o -name .svn -prune -o -type d \
      -print 2>/dev/null | sed 's@^.*/@@'
  fi
}

# Binding to redraw line after fzf closes (printf '\e[5n')
bind '"\e[0n": redraw-current-line'

# Fallback completion function
# Records _fzf_orig_completion_[command]="complete <opts> -F function #<command>"
# Also if has a 'nospace' option, and not already in the string, add to __fzf_nospace_commands string
__fzf_orig_completion_filter() {
  sed 's/^\(.*-F\) *\([^ ]*\).* \([^ ]*\)$/export _fzf_orig_completion_\3="\1 %s \3 #\2"; [[ "\1" = *" -o nospace "* ]] \&\& [[ ! "$__fzf_nospace_commands" = *" \3 "* ]] \&\& __fzf_nospace_commands="$__fzf_nospace_commands \3 ";/' |
  awk -F= '{OFS = FS} {gsub(/[^A-Za-z0-9_= ;]/, "_", $1);}1'
}

# Handle previous completion funcs
_fzf_handle_dynamic_completion() {
  local cmd ret orig orig_var orig_cmd orig_complete
  cmd="$1"
  shift
  orig_cmd="$1"
  orig_var="_fzf_orig_completion_$cmd"
  orig="${!orig_var##*#}"  # trim comment
  if [ -n "$orig" ] && type "$orig" > /dev/null 2>&1; then
    $orig "$@"  # call completion command
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

# The name of FZF command
__fzfcmd_complete() {
  [ -n "$TMUX_PANE" ] && [ "${FZF_TMUX:-0}" != 0 ] && [ ${LINES:-40} -gt 15 ] &&
    echo "fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}" || echo "fzf"
}

# Path completion
# Takes just two arguments -- the compgen command, and fzf options
__fzf_generic_path_completion() {
  local cur base dir leftover matches trigger cmd fzf opts varcomp generator
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  COMPREPLY=()
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  [ ${#COMP_WORDS[@]} -ge 1 ] && cur="${COMP_WORDS[COMP_CWORD]}" # cmd line word under cursor

  # Complete paths and variables
  varcomp=false
  [[ "$cur" == '$'* ]] && varcomp=true
  if [[ "$cur" == *"$trigger" ]]; then
    base=${cur:0:${#cur}-${#trigger}}
    eval "base=$base"
    [[ $base = *"/"* ]] && dir="$base"
    while true; do
      if [ -z "$dir" ] || [ -d "$dir" ]; then
        # Changed functionality here: make suffix dependent on whether
        # or not the item is a directory -- if so, slash, if not, space
        # The suffix used to be argument $3
        leftover=${base/#"$dir"}
        leftover=${leftover/#\/}
        [ -z "$dir" ] && dir='.'
        dir="${dir%/}"
        if $varcomp; then  # variable completion
          generator="compgen -v"
          leftover="${cur:1}"  # omit the $
          opts="+m"  # one at a time
        else
          generator="$1 $(printf %q "$dir")"
          opts="--prompt=$(printf %q "$dir")/ $2"
        fi
        count=0
        matches=$(eval "$generator" | tr -s '/' | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $opts -q "$leftover" | while read -r item; do
          count=$((count + 1))
          if $varcomp; then
            printf "%q" ${!item}  # no spaces
          else
            item="${dir}/${item%/}"
            [ -d "$item" ] && printf "%q/" "$item" || printf "%q " "$item"
          fi
          done)

        # If the command (i.e. word on first line of shell) is a
        # nospace command, add space.... what? This must be a bug, right?
        # [[ "$__fzf_nospace_commands" = *" ${COMP_WORDS[0]} "* ]] && matches="$matches "
        if [ -n "$matches" ]; then
          COMPREPLY=( "$matches" )
        else
          COMPREPLY=( "$cur" )
        fi
        printf '\e[5n' # redraws terminal line
        return 0
      fi
      dir=$(dirname "$dir")
      [[ "$dir" =~ /$ ]] || dir="$dir"/
    done

  # Trigger not active, defer to default completion
  else
    shift
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

# Generic completion, suitable for more special cases
_fzf_complete() {
  local cur selected trigger cmd fzf post
  post="$(caller 0 | awk '{print $2}')_post"   # the func name, with a _post suffix
  type -t "$post" > /dev/null 2>&1 || post=cat # empty
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  [ ${#COMP_WORDS[@]} -ge 1 ] && cur="${COMP_WORDS[COMP_CWORD]}"

  # Trigger active, collect standard input (the lone 'cat') and
  # run fzf with those options
  if [[ "$cur" == *"$trigger" ]]; then
    cur=${cur:0:${#cur}-${#trigger}}
    selected=$(cat | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $1 -q "$cur" | $post | tr '\n' ' ')
    selected=${selected% } # Strip trailing space not to repeat "-o nospace"

    if [ -n "$selected" ]; then
      COMPREPLY=("$selected")
    else
      COMPREPLY=("$cur")
    fi
    printf '\e[5n'
    return 0

  # Trigger not active, defer to default completion
  else
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

###########################################################
# Completion functions
###########################################################
# Generic path completion
_fzf_path_completion() {
  __fzf_generic_path_completion _fzf_compgen_path "-m" "$@"
}

# Directory name completion
_fzf_dir_completion() {
  __fzf_generic_path_completion _fzf_compgen_dir "+m" "$@"
}

# FZF option completion
# Change default behavior, now always complete options whether
# or not dash on line, and always use fuzzy complete
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
    --pointer
    --marker
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

# Process id completion
# TODO: Expand to other versions of 'kill' command
_fzf_kill_completion() {
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

# Host completion
_fzf_host_completion() {
  _fzf_complete +m -- "$@" < <(
    cat <(cat ~/.ssh/config ~/.ssh/config.d/* /etc/ssh/ssh_config 2> /dev/null | command grep -i '^\s*host\(name\)\? ' | awk '{for (i = 2; i <= NF; i++) print $1 " " $i}' | command grep -v '[*?]') \
        <(command grep -oE '^[[a-z0-9.,:-]+' ~/.ssh/known_hosts | tr ',' '\n' | tr -d '[' | awk '{ print $1 " " $1 }') \
        <(command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0') |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

# Exported variable name completion
_fzf_var_completion() {
  # _fzf_complete '+m' "$@" < <(compgen -v)  # original override
  _fzf_complete -m -- "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

# Alias completion
_fzf_alias_completion() {
  # _fzf_complete '+m' "$@" < <(compgen -a)  # original override
  _fzf_complete -m -- "$@" < <(
    alias | sed 's/=.*//' | sed 's/.* //'
  )
}

# Bindings completion
_fzf_bind_completion() {
  _fzf_complete '+m' "$@" < <(bind -l)
}

# Function name completion
_fzf_function_completion() {
  _fzf_complete '+m' "$@" < <(compgen -a)
}

# Commands completion, including executables on PATH and functions
_fzf_command_completion() {
  [ -r $HOME/.fzf.commands ] || compgen -c | grep -v '[!.:{}]' >$HOME/.fzf.commands
  _fzf_complete '+m' "$@" < <(cat \
    <(find -L . -mindepth 1 -maxdepth 1 -type f -executable -print) \
    <(tac $HOME/.fzf.commands | sed 's/$/ /') \
  )
}

# Shell option completion
_fzf_shopt_completion() {
  _fzf_complete '+m' "$@" < <(shopt | cut -d' ' -f1 | cut -d$'\t' -f1)
}

# Git completion, includes command names
_fzf_git_completion() {
  _fzf_complete '+m' "$@" < <(cat \
    <(_fzf_compgen_path .) \
    <(git commands | sed 's/$/ ::command/g' | column -t) \
  )
}
_fzf_git_completion_post() {
  cat | sed 's/::command *$//g' | sed 's/ *$//g'
}

# CDO completion, includes command names
# WARNING: For some reason mac sed fails in regex
# search for 's/ \+(.*) *$' but not GNU sed, so break this in two
_fzf_cdo_completion() {
  _fzf_complete '+m' "$@" < <(cat \
    <(_fzf_compgen_path .) \
    <(cdo --operators | sed 's/[ ]*[^ ]*$//g' | \
      sed 's/^\([^ ]*[ ]*\)\(.*\)$/\1(\2) /g' | \
      tr '[:upper:]' '[:lower:]'))
}
_fzf_cdo_completion_post() {
  cat | sed 's/(.*) *$//g' | sed 's/ *$//g'
}

# FZF options
complete -o default -F _fzf_opts_completion 'fzf'

d_cmds="${FZF_COMPLETION_DIR_COMMANDS:-cd pushd rmdir}"

# Preserve existing completion
eval "$(complete |
  sed -E '/-F/!d; / _fzf/d; '"/ ($(echo $d_cmds $a_cmds $x_cmds | sed 's/ /|/g; s/+/\\+/g'))$/"'!d' |
  __fzf_orig_completion_filter)"

if type _completion_loader > /dev/null 2>&1; then
  _fzf_completion_loader=1
fi

__fzf_defc() {
  local cmd func opts orig_var orig def
  cmd="$1"
  func="$2"
  opts="$3"
  orig_var="_fzf_orig_completion_${cmd//[^A-Za-z0-9_]/_}"  # set by eval in _fzf_setup_completion
  orig="${!orig_var}"
  if [ -n "$orig" ]; then
    printf -v def "$orig" "$func"
    eval "$def"
  else
    complete -F "$func" $opts "$cmd"
  fi
}

# Anything
complete -D -F _fzf_path_completion -o nospace -o default -o bashdefault
# __fzf_defc "$cmd" _fzf_path_completion "-o default -o bashdefault"  # original

# Commands
complete -E -F _fzf_command_completion -o nospace -o default -o bashdefault

# Directory
for cmd in $d_cmds; do
  __fzf_defc "$cmd" _fzf_dir_completion "-o nospace -o dirnames"
  # complete -F _fzf_dir_completion -o nospace -o dirnames "$cmd"  # custom
done

# Remove old stuff
unset cmd d_cmds a_cmds x_cmds

# Handle fallback completion with custom completion functions
_fzf_setup_completion() {
  local kind fn cmd
  kind=$1
  fn=_fzf_${1}_completion
  if [[ $# -lt 2 ]] || ! type -t "$fn" > /dev/null; then
    echo "usage: ${FUNCNAME[0]} kind COMMANDS..."
    return 1
  fi
  shift
  for cmd in "$@"; do
    eval "$(complete -p "$cmd" 2> /dev/null | grep -v "$fn" | __fzf_orig_completion_filter)"
    case "$kind" in
      # NOTE: Used to have -a for alias and -v for var but this caused weird
      # bug where builtin options get printed after selection.
      var) __fzf_defc "$cmd" "$fn" "-o default -o nospace" ;;  # the -v flag caused weird bug
      dir) __fzf_defc "$cmd" "$fn" "-o dirnames -o nospace" ;;
      *)   __fzf_defc "$cmd" "$fn" "-o default -o bashdefault" ;;
    esac
  done
}

# Custom complection setup
_fzf_setup_completion 'var'      export unset
_fzf_setup_completion 'alias'    alias unalias
_fzf_setup_completion 'host'     ssh telnet
_fzf_setup_completion 'function' function
_fzf_setup_completion 'git'      git
_fzf_setup_completion 'cdo'      cdo
_fzf_setup_completion 'kill'     kill
_fzf_setup_completion 'bind'     bind
_fzf_setup_completion 'shopt'    shopt
_fzf_setup_completion 'command'  help man type which

fi
