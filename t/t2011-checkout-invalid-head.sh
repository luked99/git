#!/bin/sh

test_description='checkout switching away from an invalid branch'

. ./test-lib.sh

test_expect_success 'setup' '
	echo hello >world &&
	git add world &&
	git commit -m initial
'

test_expect_success 'checkout should not start branch from a tree' '
	test_must_fail git checkout -b newbranch master^{tree}
'

test_expect_success 'checkout master from invalid HEAD' '
	echo $_z40 >.git/HEAD &&
	git checkout master --
'

test_expect_success 'create ref directory/file conflict scenario' '
	git update-ref refs/heads/outer/inner master &&

	# do not rely on symbolic-ref to get a known state,
	# as it may use the same code we are testing
	reset_to_df () {
		echo "ref: refs/heads/outer" >.git/HEAD
	}
'

test_expect_failure 'checkout away from d/f HEAD (to branch)' '
	reset_to_df &&
	git checkout master
'

test_expect_failure 'checkout away from d/f HEAD (to detached)' '
	reset_to_df &&
	git checkout --detach master
'

test_done
