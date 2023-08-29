#!/usr/bin/env bash

set -Eeuo pipefail  # See the meaning in scripts/README.md
# set -x  # Print each command

#-----------------------------------------------------------------------------

script_path="$0"
script=$(basename "$script_path")
script_dir=$(dirname "$script_path")

run_dir="$PWD"
cd "$script_dir"

pkg_src_root=$(readlink -e ../..)
pkg_src_root_name=$(basename "$pkg_src_root")

#-----------------------------------------------------------------------------

error ()
{
    printf "\n$script: ERROR: $*\n" 1>&2
    exit 1
}

#-----------------------------------------------------------------------------

f=$(git diff --name-status --diff-filter=R HEAD "$pkg_src_root")

if [ -n "${f-}" ]
then
    error "there are renamed files in the tree."                            \
          "\nYou should check them in before preparing a release package."  \
          "\nSpecifically:\n\n$f"
fi

f=$(git ls-files --others --exclude-standard "$pkg_src_root")

if [ -n "${f-}" ]
then
    error "there are untracked files in the tree."             \
          "\nYou should either remove or check them in"        \
          "before preparing a release package."                \
          "\nSpecifically:\n\n$f"                              \
          "\n\nYou can also see the file list by running:"     \
          "\n    (cd \"$pkg_src_root\" ; git clean -d -n)"     \
          "\n\nAfter reviewing (be careful!),"                 \
          "you can remove them by running:"                    \
          "\n    (cd \"$pkg_src_root\" ; git clean -d -f)"     \
          "\n\nNote that \"git clean\" without \"-x\" option"  \
          "does not see the files from the .gitignore list."
fi

f=$(git ls-files --others "$pkg_src_root")

if [ -n "${f-}" ]
then
    error "there are files in the tree, ignored by git,"                   \
          "based on .gitignore list."                                      \
          "\nThis repository is not supposed to have the ignored files."   \
          "\nYou need to remove them before preparing a release package."  \
          "\nSpecifically:\n\n$f"                                          \
          "\n\nYou can also see the file list by running:"                 \
          "\n    (cd \"$pkg_src_root\" ; git clean -d -x -n)"              \
          "\n\nAfter reviewing (be careful!),"                             \
          "you can remove them by running:"                                \
          "\n    (cd \"$pkg_src_root\" ; git clean -d -x -f)"
fi

f=$(git ls-files --modified "$pkg_src_root")

if [ -n "${f-}" ]
then
    error "there are modified files in the tree."                           \
          "\nYou should check them in before preparing a release package."  \
          "\nSpecifically:\n\n$f"
fi

#-----------------------------------------------------------------------------

# Search for the text files with DOS/Windows CR-LF line endings

# -r     - recursive
# -l     - file list
# -q     - status only
# -I     - Ignore binary files
# -U     - don't strip CR from text file by default
# $'...' - string literal in Bash with C semantics ('\r', '\t')

if [ "$OSTYPE" = linux-gnu ] && grep -rqIU $'\r$' "$pkg_src_root"/*
then
    grep -rlIU $'\r$' "$pkg_src_root"/*

    error "there are text files with DOS/Windows CR-LF line endings." \
          "You can fix them by doing:" \
          "\ngrep -rlIU \$'\\\\r\$' \"$pkg_src_root\"/* | xargs dos2unix"
fi

# For some reason "--exclude=\*.mk" does not work here

exclude_urg="--exclude-dir=urgReport"
exclude_urg_and_mk="$exclude_urg --exclude=*.mk"

if grep -rqI $exclude_urg_and_mk $'\t' "$pkg_src_root"/*
then
    grep -rlI $exclude_urg_and_mk $'\t' "$pkg_src_root"/*

    error "there are text files with tabulation characters." \
          "\nTabs should not be used." \
          "\nDevelopers should not need to configure the tab width" \
          " of their text editors in order to be able to read source code." \
          "\nPlease replace the tabs with spaces" \
          "before checking in or creating a package." \
          "\nYou can find them by doing:" \
          "\ngrep -rlI $exclude_urg_and_mk \$'\\\\t' \"$pkg_src_root\"/*" \
          "\nYou can fix them by doing the following," \
          "but make sure to review the fixes:" \
          "\ngrep -rlI $exclude_urg_and_mk \$'\\\\t' \"$pkg_src_root\"/*" \
          "| xargs sed -i 's/\\\\t/    /g'"
fi

if grep -rqI $exclude_urg '[[:space:]]\+$' "$pkg_src_root"/*
then
    grep -rlI $exclude_urg '[[:space:]]\+$' "$pkg_src_root"/*

    error "there are spaces at the end of line, please remove them." \
          "\nYou can fix them by doing:" \
          "\ngrep -rlI $exclude_urg '[[:space:]]\\\\+\$' \"$pkg_src_root\"/*" \
          "| xargs sed -i 's/[[:space:]]\\\\+\$//g'"
fi

#-----------------------------------------------------------------------------

# A workaround for a find problem when running bash under Microsoft Windows

find_to_run=find
true_find=/usr/bin/find

if [ -x "$true_find" ]
then
    find_to_run="$true_find"
fi

#-----------------------------------------------------------------------------

$find_to_run "$pkg_src_root" \
    -not -wholename "./.git" \
    -name '[0-9][0-9]_*.bash' \
    -not -name '[0-9][0-9]_*source_bash' \
        | while read bash_script
do
    local_redirect="$pkg_src_root/scripts/steps/local_redirect.bash_template"

    cmp --silent -- "$bash_script" "$local_redirect" \
        || error "\"$bash_script\" is not the same as \"$local_redirect\""

    [ -x "$bash_script" ] \
        || error "\"$bash_script\" is not executable. Run: chmod +x \"$bash_script\""
done

#-----------------------------------------------------------------------------

tgt_pkg_dir=$(mktemp -d)
package=${pkg_src_root_name}_$(date '+%Y%m%d')
package_path="$tgt_pkg_dir/$package"

mkdir "$package_path"
cp -r "$pkg_src_root"/* "$pkg_src_root"/.gitignore "$package_path"

$find_to_run "$package_path" -name '*.sv'  \
    | xargs -n 1 sed -i '/START_SOLUTION/,/END_SOLUTION/d'

#-----------------------------------------------------------------------------

if ! command -v zip &> /dev/null
then
    printf "$script: cannot find zip utility"

    if [ "$OSTYPE" = "msys" ]
    then
        printf "\n$script: download zip for Windows from https://sourceforge.net/projects/gnuwin32/files/zip/3.0/zip-3.0-setup.exe/download"
        printf "\n$script: then add zip to the path: %s" '%PROGRAMFILES(x86)%\GnuWin32\bin'
    fi

    exit 1
fi

#-----------------------------------------------------------------------------

rm -rf "$run_dir/$pkg_src_root_name"_*.zip

cd "$tgt_pkg_dir"
zip -r "$run_dir/$package.zip" "$package"
