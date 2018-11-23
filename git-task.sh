#!/bin/sh
# git-task - issue tracker for git.
#
# This script is Free Software under the non-terms of
# the Anti-License. Do whatever the fuck you want.

# FIXME: git-stash changes the ctime of files. This causes vim to think that 
# files have changes. Find a way to avoid this, if possible.

_TASKBRANCH="${TASKBRANCH:-tasks}"
_DEFAULT_TASK_ADD_ARGS=(${DEFAULT_TASK_ADD_ARGS:-})
_DEBUG="${DEBUG:-false}"
_TASKRC="${TASKRC:-.taskrc}"

log () {
  echo $* >&1
}

error () {
  echo $* >&2
  exit 1
}

branch_exists () {
    if [[ -z "$(git branch --list $1)" ]]; then
        return 0
    else
        return 1
    fi
}

current_branch () {
    git symbolic-ref HEAD --short 2>/dev/null
}

get_worktree_path () {
    git worktree list --porcelain | (
        unset path branch worktree is_correct_branch  
        while read line ; do
            case "$line" in
              branch*)
                  # line to array
                  line_=($line)
                  # get the branch path
                  branch_=${line_[1]}
                  # branch path to array
                  branch_=(${branch_//\// })
                  # get branch name
                  branch=${branch_[-1]}
                  if [ "${branch}" == $1 ]; then
                      is_correct_branch=true
                  fi
                  ;;
              worktree*)
                  # line to array
                  line_=($line)
                  # get the branch path
                  worktree=${line_[1]}
                  ;;
              *)
              ;;
            esac
            if [ "${is_correct_branch}" = true ]; then
                break
            fi
        done
        if [ "${is_correct_branch}" = true ]; then
            path="$worktree"
        fi
        [ -n "$path" ] && echo " $path" || echo
    )
}


has_worktree () {
  worktree=$(get_worktree_path $1)
  if [ -z "${worktree}" ]; then
      # no worktree
      echo 0
  else
      # there is one
      echo 1
  fi
}



# stash the current branch and remember its name
prepare () {
  $_DEBUG && log "Preparing transaction..."
  _OLDDIR="$PWD"
  if [ $_BRANCH_HAS_WORKTREE -eq 0 ]; then
    $_DEBUG && log "Checking for .git directory..."
    # TODO: currently only works in the git root directory.
    cd $( git rev-parse --show-toplevel )
    if [[ ! -d .git ]]; then
      error "Git dir not found. Is this the root directory of the repository?"
      exit 1
    fi

    # source env file if exists
    [ -f ${_TASKBRANCH}.config ] && source ./${_TASKBRANCH}.config
    # if this fails, something is horribly wrong.
    $_DEBUG && log "Stashing current branch..."
    git stash save --include-untracked \
      "git-task stash. You should never see this." &>/dev/null
    if [[ $? -ne 0 ]]; then
      error "[FATAL] Stashing failed, bailing out. Your working directory might be dirty."
    fi

    $_DEBUG && log "Checking out task-branch..."
    git checkout  -q ${_TASKBRANCH} &>/dev/null
    if [[ $? -ne 0 ]]; then
      $_DEBUG && log "No task branch. Creating new orphan branch..."
      git checkout -q --orphan "${_TASKBRANCH}" HEAD || rollback 1
      $_DEBUG && log "Unstaging everything..."
      git rm -q --cached -r "*" || rollback 1
    fi
    cd $_OLDDIR
  else
    $_DEBUG && log "Moving to worktree."
    cd $(get_worktree_path $_TASKBRANCH)
  fi

  $_DEBUG && log "Done preparing."
}

task_commit () {
  $_DEBUG && log "Starting task transaction..."
  $_DEBUG && log "Recording task..."
  if [[ ! -d "${_TASKRC}" ]]; then
    $_DEBUG && log "Remembering that task configuration file doesn't exist."
    no_taskrc=true
  fi
  case $1 in
    add)
    task_args=$DEFAULT_TASK_ADD_ARGS
    $_DEBUG && log "Adding args: ${task_args}"
    ;;
    *)
    task_args=""
    ;;
  esac

  TASKDATA=.task TASKRC="${_TASKRC}" task $1 ${task_args[@]} ${@:2} || rollback 1
  # add and commit the changes
  $_DEBUG && log "Adding task to git..."
  git add .task "${_TASKRC}" || rollback 1
  msg="$*"
  if [ -z "$msg" ] && [ "$no_taskrc" = true ]; then
    $_DEBUG && log "Custom commit message for creating task configuration file."
    msg="Created task configuration file."
  fi
  $_DEBUG && log "Committing task..."
	git commit -q -m "${msg}" &>/dev/null || rollback 1
  $_DEBUG && log "Transaction done."
}

rollback () {
  $_DEBUG && log "Rolling back..."
  if [ $_BRANCH_HAS_WORKTREE -eq 0 ]; then
    cd $_OLDDIR
  else
    # Since we stashed, there should™ be nothing that could go wrong here.
    $_DEBUG && log "Checking out working branch..."
    git checkout -f ${_CURRENT} &>/dev/null
    if [[ $? -ne 0 ]]; then
      error "[FATAL] Couldn't rollback to previous state: checkout to ${_CURRENT} failed. There should be a stash with your uncommited changes."
    fi
    $_DEBUG && log "Applying the stash..."
    git stash pop -q
  fi

  $_DEBUG && log "Done rolling back."
  exit $1
}

# BEGIN SCRIPT

# TODO: Figure out a better way to save this than a global.
_CURRENT=$(current_branch)
_BRANCH_HAS_WORKTREE=$(has_worktree $_TASKBRANCH)

case $1 in
  editconfig)
  $_DEBUG && log "Edit config file."
  prepare
  $EDITOR "${_TASKRC}"
  $_DEBUG && log "Adding taskrc to git..."
  git add "${_TASKRC}" || rollback 1
  $_DEBUG && log "Committing task..."
	git commit -q -m "Edited task configuration file" &>/dev/null || rollback 1
  rollback
  $_DEBUG && log "Finishing transaction."
  ;;
  *)
  prepare
  task_commit $*
  rollback
  ;;
esac

exit 0

# vim: ts=2 sw=2 sts=2 et :
