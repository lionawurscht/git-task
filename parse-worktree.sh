BRANCH=${BRANCH:-"move_branch_to_worktree"}

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

echo $(has_worktree $BRANCH)

git checkout $BRANCH || cd $(get_worktree_path $BRANCH) && ls
