#!/bin/sh

#
# Converting P4 changes into patches
#
# - added, deleted, modified files
# - regular commits, shelved commits
#

test_description='git p4 format-patch'

. ./lib-git-p4.sh

# check for broken patch generation - this breaks quite easily due to Perforce's
# use of a double slash in depot paths.
patch_is_ok() {
	for i in "$@"; do
		if grep // "$i"; then
			echo "patch file $i contains //, path construction is broken" 1>&2 &&
			exit 1
		fi
		if grep '^--- a[^/]'; then
			echo "patch file $i has --- line with missing leading /" 1>&2 &&
			exit 1
		fi
		if grep '^+++ b[^/]'; then
			echo "patch file $i has +++ line with missing leading /" 1>&2 &&
			exit 1
		fi

	done
}

test_expect_success 'start p4d' '
	start_p4d
'

test_expect_success 'init depot' '
	(
		cd "$cli" &&
		echo file1 >file1 &&
		p4 add file1 &&
		p4 submit -d "change 1" &&			# cl 1
		cat >file_to_delete <<-EOF &&
		LINE1
		LINE2
		EOF
		echo "non-empty" >file_to_delete &&
		p4 add file_to_delete &&
		p4 submit -d "change 2" &&			# cl 2
		p4 edit file1 &&
		cat >>file1 <<-EOF &&
		LINE1
		LINE2
		EOF
		p4 submit -d "change 3" &&			# cl 3
		p4 delete file_to_delete &&
		echo "file2" >file2 &&
		p4 add file2 &&
		p4 submit -d "change 4"				# cl 4
	)
'

# apply a patch, with --use-client-spec, so files should be mapped in
# the same as done by Perforce ("file", not "/depot/file")
test_expect_success 'patches on submitted changes' '
	test_when_finished cleanup_git &&
	mkdir -p "$git" &&
	(
		cd "$git" &&
		git init &&
		P4CLIENT=client git p4 format-patch --use-client-spec --output "$PWD/output" 1 2 3 4 &&
		patch_is_ok output/*.patch &&
		patch -p1 <output/1.patch &&
		test_path_is_file file1 &&

		patch -p1 <output/2.patch &&
		test_path_is_file file_to_delete &&

		patch -p1 <output/3.patch &&
		test_path_is_file file1 &&
		test_cmp "$cli"/file1 file1 &&

		patch -p1 <output/4.patch &&
		test_path_is_missing file_to_delete
	)
'

test_expect_success 'create shelved changelists' '
	(
		cd "$cli" &&
		cat >file10 <<-EOF &&
		LINE1
		LINE2
		EOF
		p4 add file10 &&
		p4 delete file1 &&
		p4 edit file2 &&
		cat >>file2 <<-EOF &&
		LINE3
		LINE4
		EOF

		p4 shelve -i <<EOF &&
Change: new
Description:
	Test commit

	Further description
Files:
	//depot/file1
	//depot/file2
	//depot/file10
EOF
		p4 describe -s -S 5
	)
'

test_expect_success 'git am from shelved changelists, no client spec' '
	test_when_finished cleanup_git &&
	git p4 clone --destination="$git" //depot &&
	(
		cd "$git" &&
		git p4 format-patch 5 > out.patch &&
		patch_is_ok out.patch &&
		grep -q "Further description" out.patch &&
		git am out.patch &&
		test_cmp file10 "$cli/file10" &&
		test_cmp file2 "$cli/file2" &&
		test_path_is_missing file1
	)
'

test_expect_success 'create deep hierarchy to check depot path stripping' '
	(
		cd "$cli" &&
		mkdir -p a/b/c/d &&
		: >a/b/c/d/foo &&
		p4 add a/b/c/d/foo &&
		p4 submit -d "adding foo" &&			# change 6
		p4 print //depot/a/b/c/d/foo &&
		p4 edit a/b/c/d/foo &&
		echo "shelved change" >>a/b/c/d/foo &&

		p4 shelve -i <<-EOF &&			# change 7 (shelved)
		Change: new
		Client: client
		Description: A shelved change
		Files: //depot/a/b/c/d/foo
		EOF

		p4 client -i <<-EOF &&
		Client:	client2
		Root: null
		View: //depot/a/b/c/... //client2/...
		LineEnd: unix
		EOF
		p4 -c client2 client -o | grep -q a/b/c
	)
'

# clone with --use-client-spec; format-patch should honor that setting
test_expect_success 'check depot path stripping with --use-client-spec' '
	test_when_finished cleanup_git &&
	P4CLIENT=client2 git p4 clone --use-client-spec --destination="$git" //depot &&
	(
		cd "$git" &&
		test_path_is_dir d &&
		test_path_is_file d/foo &&

		P4CLIENT=client2 git p4 format-patch 7 > out.patch &&
		patch_is_ok out.patch &&
		git am out.patch &&
		test_cmp d/foo "$cli/a/b/c/d/foo"
	)
'

test_expect_success SYMLINKS 'add p4 symlink' '
	(
		cd "$cli" &&
		echo "symlink_source" >symlink_source &&
		ln -s symlink_source symlink &&
		p4 add symlink_source symlink &&
		p4 shelve -i <<EOF
Change: new
Client: client
Description: add symlink
Files:
	//depot/symlink
	//depot/symlink_source
EOF
	)
'

# adding a symlink
test_expect_success SYMLINKS 'patch adds symlink' '
	test_when_finished cleanup_git &&
	P4CLIENT=client git p4 clone --use-client-spec --destination="$git" //depot &&
	(
		cd "$git" &&
		git p4 format-patch 8 >out.patch &&
		patch -p1 <out.patch &&
		test_path_is_file symlink_source &&
		test -L symlink &&
		test $(readlink symlink) = symlink_source
	)
'

# removing a symlink
test_expect_success SYMLINKS 'remove p4 symlink - create shelved CL' '
	(
		cd "$cli" &&
		p4 revert ... && rm -f symlink symlink_source &&
		p4 unshelve -s 8 &&
		p4 submit -d "change" &&
		p4 delete symlink
		p4 shelve -i <<EOF		# shelved changelist 10
Change: new
Client: client
Description: remove symlink
Files:
	//depot/symlink
EOF
	)
'

test_expect_success SYMLINKS 'remove p4 symlink via patch' '
	test_when_finished cleanup_git && pwd &&
	cd "$cli" &&
	P4CLIENT=client git p4 clone --use-client-spec --destination="$git" //depot &&
	cd "$git" &&
	(
		test_path_is_file symlink &&
		test -L symlink &&
		test $(readlink symlink) = symlink_source &&
		git p4 format-patch 10 >out.patch &&
		patch -p1 <out.patch &&
		test_path_is_missing symlink &&
		test_path_is_file symlink_source
	)
'

# should be able to generate patch without either an existing git repo or
# a P4 client
test_expect_success 'use --depot-root' '
	workdir="$TRASH_DIRECTORY/work" &&
	mkdir -p "$workdir" &&
	(
		cd "$workdir" &&
		git p4 format-patch --depot-root //depot/a/b --output patches 6 7 &&
		for cl in 6 7
		do
			patch_is_ok patches/$cl.patch &&
			patch -p1 <patches/$cl.patch
		done &&
		test_path_is_dir c &&
		test_path_is_file c/d/foo
	) &&
	rm -fr "$workdir"
'

test_expect_success 'add binary files' '
	(
		cd "$cli" &&
		cp "$TEST_DIRECTORY/test-binary-1.png" . &&
		p4 add test-binary-1.png &&
		p4 submit -d "add binary file" &&		# change 11
		p4 edit test-binary-1.png &&
		cp "$TEST_DIRECTORY/test-binary-2.png" test-binary-1.png &&
		p4 submit -d "edit binary file"			# change 12
	)
'

test_expect_success 'patches from binary files' '
	workdir="$TRASH_DIRECTORY/work" &&
	mkdir -p "$workdir" &&
	(
		cd "$workdir" &&
		git p4 format-patch --depot-root //depot 11 > patch1.patch &&
		patch -p1 <patch1.patch &&
		test_path_is_file test-binary-1.png &&
		test_cmp test-binary-1.png "$TEST_DIRECTORY/test-binary-1.png" &&
		git p4 format-patch --depot-root //depot 12 --output outdir &&
		test_pause &&
		patch -p1 <outdir/12.patch &&
		test_cmp test-binary-1.png "$TEST_DIRECTORY/test-binary-2.png"
	)
'
test_expect_success 'kill p4d' '
	kill_p4d
'

test_done
