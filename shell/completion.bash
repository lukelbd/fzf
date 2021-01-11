#     ____      ____
#    / __/___  / __/
#   / /_/_  / / /_
#  / __/ / /_/ __/
# /_/   /___/_/ completion.bash
#
# - $FZF_TMUX               (default: 0)
# - $FZF_TMUX_OPTS          (default: empty)
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
      -name .git -prune -o -name .hg -prune -o -name .svn -prune -o \( -type d -o -type f -o -type l \) \
      -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
  fi
}
_fzf_compgen_dir() {
  if [ -n "$FZF_COMPGEN_DIR_COMMAND" ]; then
    eval "$FZF_COMPGEN_DIR_COMMAND"
  else
    command find -L "$1" \
      -maxdepth 1 -mindepth 1 \
      -name .git -prune -o -name .hg -prune -o -name .svn -prune -o -type d \
      -a -not -path "$1" -print 2>/dev/null | sed 's@^.*/@@'
  fi
}

###########################################################

# Binding to redraw line after fzf closes (printf '\e[5n')
bind '"\e[0n": redraw-current-line'

# Handle previous completion funcs
__fzf_comprun() {
  if [ "$(type -t _fzf_comprun 2>&1)" = function ]; then
    _fzf_comprun "$@"
  elif [ -n "$TMUX_PANE" ] && { [ "${FZF_TMUX:-0}" != 0 ] || [ -n "$FZF_TMUX_OPTS" ]; }; then
    shift
    fzf-tmux ${FZF_TMUX_OPTS:--d${FZF_TMUX_HEIGHT:-40%}} -- "$@"
  else
    shift
    fzf "$@"
  fi
}

# Fallback completion function
# Records _fzf_orig_completion_[command]="complete <opts> -F function #<command>"
# If has a 'nospace' option, and not already in string, add to __fzf_nospace_commands string
__fzf_orig_completion() {
  local l comp f cmd
  while read -r l; do
    if [[ "$l" =~ ^(.*\ -F)\ *([^ ]*).*\ ([^ ]*)$ ]]; then
      comp="${BASH_REMATCH[1]}"
      f="${BASH_REMATCH[2]}"
      cmd="${BASH_REMATCH[3]}"
      [[ "$f" = _fzf_* ]] && continue
      printf -v "_fzf_orig_completion_${cmd//[^A-Za-z0-9_]/_}" "%s" "${comp} %s ${cmd} #${f}"
      if [[ "$l" = *" -o nospace "* ]] && [[ ! "$__fzf_nospace_commands" = *" $cmd "* ]]; then
        __fzf_nospace_commands="$__fzf_nospace_commands $cmd "
      fi
    fi
  done
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
    if [ "$(complete -p "$orig_cmd" 2> /dev/null)" != "$orig_complete" ]; then
      __fzf_orig_completion < <(complete -p "$orig_cmd" 2> /dev/null)
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
  local cur base dir leftover matches trigger cmd opts varcomp leftover generator
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  COMPREPLY=()
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  [ ${#COMP_WORDS[@]} -ge 1 ] && cur="${COMP_WORDS[COMP_CWORD]}" # cmd line word under cursor

  # Complete paths and variables
  [[ "$cur" == '$'* ]] && varcomp=true || varcomp=false
  if [[ "$cur" == *"$trigger" ]]; then
    base=${cur:0:${#cur}-${#trigger}}
    eval "base=$base"
    [[ $base = *"/"* ]] && dir="$base"
    while true; do
      if [ -z "$dir" ] || [ -d "$dir" ]; then
        # Changed functionality here: make suffix dependent on whether
        # or not the item is a directory -- if so, slash, if not, space
        # The suffix used to be argument $3, instead use directory-dependent options.
        leftover=${base/#"$dir"}
        leftover=${leftover/#\/}
        [ -z "$dir" ] && dir='.'
        dir="${dir%/}"
        if $varcomp; then  # variable completion
          leftover="${cur:1}"  # omit the $
          generator="compgen -v"
          opts="+m"  # one at a time
        else
          generator="$1 $(printf %q "$dir")"
          opts="--prompt=$(printf %q "$dir")/ $2"
        fi
        count=0
        matches=$(eval "$generator" | tr -s '/' | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS $opts" __fzf_comprun "$4" -q "$leftover" | while read -r item; do
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
        # matches=${matches% }
        # [[ -z "$3" ]] && [[ "$__fzf_nospace_commands" = *" ${COMP_WORDS[0]} "* ]] && matches="$matches "
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
  # Split arguments around --
  local args rest str_arg i sep
  args=("$@")
  sep=
  for i in "${!args[@]}"; do
    if [[ "${args[$i]}" = -- ]]; then
      sep=$i
      break
    fi
  done
  if [[ -n "$sep" ]]; then
    str_arg=
    rest=("${args[@]:$((sep + 1)):${#args[@]}}")
    args=("${args[@]:0:$sep}")
  else
    str_arg=$1
    args=()
    shift
    rest=("$@")
  fi

  local cur selected trigger cmd post
  post="$(caller 0 | awk '{print $2}')_post"  # function name with _post suffix
  type -t "$post" > /dev/null 2>&1 || post=cat

  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  [ ${#COMP_WORDS[@]} -ge 1 ] && cur="${COMP_WORDS[COMP_CWORD]}"

  # Trigger active, collect standard input (the lone 'cat') and
  # run fzf with those options
  if [[ "$cur" == *"$trigger" ]]; then
    cur=${cur:0:${#cur}-${#trigger}}

    selected=$(FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse --bind=ctrl-z:ignore $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS $str_arg" __fzf_comprun "${rest[0]}" "${args[@]}" -q "$cur" | $post | tr '\n' ' ')
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
    _fzf_handle_dynamic_completion "$cmd" "${rest[@]}"
  fi
}

###########################################################
# Completion functions
###########################################################
_fzf_path_completion() {
  __fzf_generic_path_completion _fzf_compgen_path "-m" "$@"
}

_fzf_dir_completion() {
  __fzf_generic_path_completion _fzf_compgen_dir "+m" "$@"
}

_fzf_kill_completion() {
  local trigger=${FZF_COMPLETION_TRIGGER-'**'}
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ -z "$cur" ]]; then
    COMP_WORDS[$COMP_CWORD]=$trigger
  elif [[ "$cur" != *"$trigger" ]]; then
    return 1
  fi

  _fzf_proc_completion "$@"
}

_fzf_proc_completion() {
  _fzf_complete -m --preview 'echo {}' --preview-window down:3:wrap --min-height 15 -- "$@" < <(
    command ps -ef | sed 1d
  )
}

_fzf_proc_completion_post() {
  awk '{print $2}'
}

_fzf_host_completion() {
  _fzf_complete +m -- "$@" < <(
    command cat <(command tail -n +1 ~/.ssh/config ~/.ssh/config.d/* /etc/ssh/ssh_config 2> /dev/null | command grep -i '^\s*host\(name\)\? ' | awk '{for (i = 2; i <= NF; i++) print $1 " " $i}' | command grep -v '[*?]') \
        <(command grep -oE '^[[a-z0-9.,:-]+' ~/.ssh/known_hosts | tr ',' '\n' | tr -d '[' | awk '{ print $1 " " $1 }') \
        <(command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0') |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}

_fzf_var_completion() {
  _fzf_complete -m -- "$@" < <(
    declare -xp | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_alias_completion() {
  _fzf_complete -m -- "$@" < <(
    alias | sed 's/=.*//' | sed 's/.* //'
  )
}

_fzf_bind_completion() {
  _fzf_complete '+m' "$@" < <(bind -l)
}

_fzf_function_completion() {
  _fzf_complete '+m' "$@" < <(compgen -a)
}

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
a_cmds="
  awk cat diff diff3
  emacs emacsclient ex file ftp g++ gcc gvim head hg java
  javac ld less more mvim nvim patch perl python ruby
  sed sftp sort source tail tee uniq vi view vim wc xdg-open
  basename bunzip2 bzip2 chmod chown curl cp dirname du
  find git grep gunzip gzip hg jar
  ln ls mv open rm rsync scp
  svn tar unzip zip"

# Preserve existing completion
__fzf_orig_completion < <(complete -p $d_cmds $a_cmds 2> /dev/null)

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

# Kill completion (supports empty completion trigger)
complete -F _fzf_kill_completion -o default -o bashdefault kill

unset cmd d_cmds a_cmds

# Handle fallback completion with custom completion functions
_fzf_setup_completion() {
  local kind fn cmd
  kind=$1
  fn=_fzf_${1}_completion
  if [[ $# -lt 2 ]] || ! type -t "$fn" > /dev/null; then
    echo "usage: ${FUNCNAME[0]} path|dir|var|alias|host|proc COMMANDS..."
    return 1
  fi
  shift
  __fzf_orig_completion < <(complete -p "$@" 2> /dev/null)
  for cmd in "$@"; do
    case "$kind" in
      # NOTE: Used to have -a for alias and -v for var but this caused weird
      # bug where builtin options get printed after selection.
      # alias) __fzf_defc "$cmd" "$fn" "-a" ;;
      dir) __fzf_defc "$cmd" "$fn" "-o dirnames -o nospace" ;;
      var) __fzf_defc "$cmd" "$fn" "-o default -o nospace" ;;  # -v caused bug
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
