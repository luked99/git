#!/bin/sh

last_shelved_change() {
	p4 changes -s shelved -m1 | cut -d " " -f 2
}

test_description='git p4 unshelve'

. ./lib-git-p4.sh

test_expect_success 'start p4d' '
	start_p4d
'

test_expect_success 'init depot' '
	(
		cd "$cli" &&
		echo file1 >file1 &&
		p4 add file1 &&
		p4 submit -d "change 1"
		: > file_to_delete &&
		p4 add file_to_delete &&
		p4 submit -d "file to delete"
	)
'

test_expect_success 'initial clone' '
	git p4 clone --dest="$git" //depot/@all
'

test_expect_success 'create shelved changelist' '
	(
		cd "$cli" &&
		p4 edit file1 &&
		echo "a change" >>file1 &&
		echo "new file" > file2 &&
		p4 add file2 &&
		p4 delete file_to_delete &&
		p4 opened &&
		p4 shelve -i <<EOF
Change: new
Description:
	Test commit

	Further description
Files:
	//depot/file1
	//depot/file2
	//depot/file_to_delete
EOF

	) &&
	(
		cd "$git" &&
		change=$(last_shelved_change) &&
		git p4 unshelve $change &&
		git show refs/remotes/p4/unshelved/$change | grep -q "Further description" &&
		git cherry-pick refs/remotes/p4/unshelved/$change &&
		test_path_is_file file2 &&
		test_cmp file1 "$cli"/file1 &&
		test_cmp file2 "$cli"/file2 &&
		test_path_is_missing file_to_delete
	)
'

test_expect_success 'update shelved changelist and re-unshelve' '
	test_when_finished cleanup_git &&
	(
		cd "$cli" &&
		change=$(last_shelved_change) &&
		echo "file3" >file3 &&
		p4 add -c $change file3 &&
		p4 shelve -i -r <<EOF &&
Change: $change
Description:
	Test commit

	Further description
Files:
	//depot/file1
	//depot/file2
	//depot/file3
	//depot/file_to_delete
EOF
		p4 describe $change
	) &&
	(
		cd "$git" &&
		change=$(last_shelved_change) &&
		git p4 unshelve $change &&
		git diff refs/remotes/p4/unshelved/$change.0 refs/remotes/p4/unshelved/$change | grep -q file3
	)
'

test_expect_success 'kill p4d' '
	kill_p4d
'

test_done
