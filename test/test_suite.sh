#!/usr/bin/env bash
# GOSH Comprehensive Automated Test Suite
# Tests functionality of GOSH (Native Unix Shell in Goose)

set -e

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
GOSH=${GOSH-"$REPO_ROOT/bin/gosh"}

if [ ! -f "$GOSH" ]; then
    printf 'Error: GOSH binary is missing or not a regular file: %s\n' "$GOSH" >&2
    printf 'Build it with: goose build -o bin/gosh src/gosh.goose (from %s)\nOr set GOSH to an executable path.\n' "$REPO_ROOT" >&2
    exit 1
fi
if [ ! -x "$GOSH" ]; then
    printf 'Error: GOSH binary is not executable: %s\nCheck its permissions (chmod +x) or set GOSH to an executable path.\n' "$GOSH" >&2
    exit 1
fi

TEST_TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gosh-tests.XXXXXXXX")
trap 'rm -rf -- "$TEST_TMP_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Expand these paths inside GOSH so filename characters stay literal.
export TMP_FILE="$TEST_TMP_DIR/output.txt"
export TMP_ERR="$TEST_TMP_DIR/error.txt" 
PASSED=0
FAILED=0

run_test() {
    local test_name="$1"
    local cmd="$2"
    local expected="$3"

    local expected_status="${4:-0}"
    local actual actual_status
    if actual=$("$GOSH" -c "$cmd" 2>&1); then
        actual_status=0
    else
        actual_status=$?
    fi

    if [ "$actual" = "$expected" ] && [ "$actual_status" -eq "$expected_status" ]; then
        echo -e "\033[32m[PASS]\033[0m $test_name"
        PASSED=$((PASSED + 1))
    else
        echo -e "\033[31m[FAIL]\033[0m $test_name"
        echo "  Command:  $cmd"
        echo "  Expected: [$expected]"
        echo "  Actual:   [$actual]"
        echo "  Expected status: $expected_status"
        echo "  Actual status:   $actual_status"
        FAILED=$((FAILED + 1))
    fi
}

echo "================================================"
echo " Running GOSH Automated Test Suite"
echo " Target Binary: $GOSH"
echo "================================================"

# 1. Echo Builtin
run_test "echo simple" "echo hello world" "hello world"
run_test "echo -n flag" "echo -n foo && echo bar" "foobar"
run_test "echo -e escapes" "echo -e 'a\tb'" "a	b"

# 2. PWD and CD
run_test "pwd builtin" "pwd" "$(pwd)"
run_test "cd and oldpwd" "cd /tmp && pwd && cd - > /dev/null && pwd" "/tmp
$(pwd)"

# 3. Variables & Expansions
run_test "variable assignment" "x=123 && echo \$x" "123"
run_test "variable in double quotes" "x=world && echo \"hello \$x\"" "hello world"
run_test "variable in single quotes" "x=world && echo 'hello \$x'" "hello \$x"
run_test "default parameter expansion" "unset UNSET_V && echo \${UNSET_V:-fallback}" "fallback"
run_test "string length expansion" "MSG=hello && echo \${#MSG}" "5"
run_test "arithmetic expansion addition" "echo \$(( 10 + 32 ))" "42"
run_test "arithmetic precedence" "echo \$(( 2 + 3 * 4 ))" "14"
run_test "arithmetic parentheses" "echo \$(( (2 + 3) * 4 ))" "20"
run_test "arithmetic grouped product unquoted" 'echo $(((2+3)*(4+5)))' "45"
run_test "arithmetic grouped product quoted" 'echo "$(((2+3)*(4+5)))"' "45"
run_test "arithmetic chained groups unquoted" 'echo $(((2+3)*(4+5)+(6-2)*(3+1)))' "61"
run_test "arithmetic chained groups quoted" 'echo "$(((2+3)*(4+5)+(6-2)*(3+1)))"' "61"
run_test "arithmetic nested closing groups unquoted" 'echo $((2*((3+4)) + 1))' "15"
run_test "arithmetic nested closing groups quoted" 'echo "$((2*((3+4)) + 1))"' "15"
run_test "arithmetic nested outer group unquoted" 'echo $((((2+3)*(4+5))))' "45"
run_test "arithmetic nested outer group quoted" 'echo "$((((2+3)*(4+5))))"' "45"
run_test "arithmetic left associative subtraction unquoted" 'echo $((20-5-3))' "12"
run_test "arithmetic left associative subtraction quoted" 'echo "$((20-5-3))"' "12"
run_test "arithmetic left associative division unquoted" 'echo $((24/4/2))' "3"
run_test "arithmetic left associative division quoted" 'echo "$((24/4/2))"' "3"
run_test "arithmetic spaced unary minus unquoted" 'echo $((2 * - 3 + 10))' "4"
run_test "arithmetic spaced unary minus quoted" 'echo "$((2 * - 3 + 10))"' "4"
run_test "arithmetic unary grouped term unquoted" 'echo $((- (2+3) * 4))' "-20"
run_test "arithmetic unary grouped term quoted" 'echo "$((- (2+3) * 4))"' "-20"
run_test "arithmetic remainder unary minus unquoted" 'echo $((7 % - 3))' "1"
run_test "arithmetic remainder unary minus quoted" 'echo "$((7 % - 3))"' "1"
run_test "arithmetic precedence mixed groups unquoted" 'echo $(((2+3)+4*(5-2)))' "17"
run_test "arithmetic precedence mixed groups quoted" 'echo "$(((2+3)+4*(5-2)))"' "17"
run_test "arithmetic quoted surrounding text" 'echo "result=$((2+3)):$((4*5))"' "result=5:20"
run_test "special var status 0" "echo success && echo \$?" "success
0"
run_test "special var status error" "false || echo \$?" "1"
run_test "failed command status" "false" "" 1
run_test "explicit exit status" "exit 7" "" 7

# 4. Command Substitution
run_test "command substitution simple" "echo \$(echo nested)" "nested"
run_test "command substitution with pipe" "echo \$(echo hello | tr 'a-z' 'A-Z')" "HELLO"
run_test "backtick substitution" "echo \`echo backtick\`" "backtick"

# 5. Redirection
run_test "redirect stdout >" "echo line1 > \"\$TMP_FILE\" && cat \"\$TMP_FILE\"" "line1"
run_test "redirect append >>" "echo line2 >> \"\$TMP_FILE\" && cat \"\$TMP_FILE\"" "line1
line2"
run_test "redirect stdin <" "cat < \"\$TMP_FILE\"" "line1
line2"
run_test "redirect stderr 2>" "sh -c 'echo error >&2; exit 1' 2> \"\$TMP_ERR\" || cat \"\$TMP_ERR\"" "error"
run_test "redirect 2>&1" "sh -c 'echo error >&2; exit 1' 2>&1 | grep error" "error"

# 6. Pipelines
run_test "two-stage pipeline" "echo -e 'banana\napple' | sort" "apple
banana"
run_test "three-stage pipeline" "echo -e '3\n1\n2' | sort | head -n 1" "1"
run_test "builtin in pipeline" "alias ll='ls -la' && alias | grep ll" "alias ll='ls -la'"
run_test "set in pipeline" "MYVAR=findme && set | grep MYVAR" "MYVAR=findme"

# 7. Subshells
run_test "subshell isolation" "(cd /tmp && pwd) && pwd" "/tmp
$(pwd)"
run_test "subshell redirection" "(echo sub1; echo sub2) > \"\$TMP_FILE\" && cat \"\$TMP_FILE\"" "sub1
sub2"

# 8. Conditionals (IF/THEN/ELSE/FI)
run_test "if true branch" "if test 1 -eq 1; then echo yes; else echo no; fi" "yes"
run_test "if false branch" "if test 1 -eq 2; then echo yes; else echo no; fi" "no"
run_test "if without else" "if test 'a' = 'a'; then echo matched; fi" "matched"

# 9. Loops (WHILE and FOR)
run_test "for loop" "for i in alpha beta gamma; do echo \$i; done" "alpha
beta
gamma"
run_test "while loop" "c=0; while test \$c -lt 3; do echo \$c; c=\$((c + 1)); done" "0
1
2"
run_test "for loop redirected" "for i in 1 2; do echo item_\$i; done > \"\$TMP_FILE\" && cat \"\$TMP_FILE\"" "item_1
item_2"

# Compound redirections must preserve shell state and restore descriptors.
run_test "redirected for preserves state" 'x=before; for i in one; do x=after; done > /dev/null; echo "$x"; echo "$i"' "after
one"
run_test "redirected if preserves state" 'x=before; if test 1 -eq 1; then x=after; echo hidden; fi > /dev/null; echo "$x"' "after"
run_test "redirected else preserves state" 'x=before; if test 1 -eq 2; then x=wrong; else x=after; fi > /dev/null; echo "$x"' "after"
run_test "redirected while preserves state" 'c=0; while test $c -lt 2; do c=$((c + 1)); echo hidden; done > /dev/null; echo "$c"' "2"
run_test "compound restores stdout after body failure" 'if test 1 -eq 1; then test 1 -eq 2; fi > /dev/null; echo "$?"; echo visible' "1
visible"
run_test "redirected subshell still isolates state" 'x=before; (x=after; echo hidden) > /dev/null; echo "$x"' "before"

# A file cannot be traversed as a directory: deterministic failing paths.
echo fixture > "$TMP_FILE"
run_test "for redirect failure skips body and restores stdout" "x=before; for i in one; do x=after; done > /dev/null < $TMP_FILE/missing; echo \$?; echo \$x" "1
before"
run_test "if redirect failure skips condition and body" "x=before; if x=condition; then x=after; fi > /dev/null < $TMP_FILE/missing; echo \$?; echo \$x" "1
before"
run_test "while redirect failure skips condition and body" "x=before; while x=condition; test 1 -eq 2; do x=after; done > /dev/null < $TMP_FILE/missing; echo \$?; echo \$x" "1
before"
run_test "compound output open failure" "x=before; for i in one; do x=after; done > /dev/null > $TMP_FILE/missing; echo \$?; echo \$x" "1
before"
run_test "compound restores stderr after partial failure" "for i in one; do echo wrong; done > /dev/null 2> $TMP_ERR < $TMP_FILE/missing; echo \$?; sh -c 'echo restored >&2'" "1
restored"
rm -f "$TMP_FILE" "$TMP_ERR"

# Contribution #5: elif chains and nested control structures.
run_test "elif first branch wins" 'if test 1 -eq 1; then echo first; elif test 1 -eq 1; then echo wrong; else echo wrong; fi' "first"
run_test "elif true branch" 'if test 1 -eq 2; then echo wrong; elif test 2 -eq 2; then echo second; else echo wrong; fi' "second"
run_test "elif later branch" 'if test 1 -eq 2; then echo wrong; elif test 2 -eq 3; then echo wrong; elif test 3 -eq 3; then echo third; fi' "third"
run_test "elif all false with else" 'if test 1 -eq 2; then echo wrong; elif test 2 -eq 3; then echo wrong; else echo fallback; fi' "fallback"
run_test "elif all false without else" 'if test 1 -eq 2; then echo wrong; elif test 2 -eq 3; then echo wrong; fi; echo after' "after"
run_test "elif skipped condition has no side effects" 'if test 1 -eq 1; then echo selected; elif echo wrong; then echo wrong; fi' "selected"
run_test "elif selected body status" 'if test 1 -eq 2; then echo wrong; elif test 1 -eq 1; then test 1 -eq 2; fi; echo $?' "1"
run_test "nested if then branch" 'if test 1 -eq 1; then if test 1 -eq 2; then echo wrong; else echo inner; fi; echo outer; else echo wrong; fi' "inner
outer"
run_test "nested if else branch" 'if test 1 -eq 2; then echo wrong; else if test 1 -eq 1; then echo inner; else echo wrong; fi; echo outer; fi' "inner
outer"
run_test "nested elif binding" 'if test 1 -eq 1; then if test 1 -eq 2; then echo wrong; elif test 1 -eq 1; then echo inner; fi; elif test 1 -eq 1; then echo wrong; fi' "inner"
run_test "for within for" 'for i in a b; do for j in 1 2; do echo $i$j; done; echo end_$i; done' "a1
a2
end_a
b1
b2
end_b"
run_test "if within for" 'for i in a b; do if test "$i" = a; then echo first; elif test "$i" = b; then echo second; fi; done' "first
second"
run_test "for within if" 'if test 1 -eq 1; then for i in a b; do echo $i; done; echo after; fi' "a
b
after"
run_test "while within while" 'i=0; while test $i -lt 2; do j=0; while test $j -lt 2; do echo $i$j; j=$((j + 1)); done; i=$((i + 1)); done' "00
01
10
11"
run_test "for within while" 'i=0; while test $i -lt 2; do for j in a b; do echo $i$j; done; i=$((i + 1)); done' "0a
0b
1a
1b"
run_test "while within for" 'for i in a b; do j=0; while test $j -lt 2; do echo $i$j; j=$((j + 1)); done; done' "a0
a1
b0
b1"
run_test "if within while" 'i=0; while test $i -lt 2; do if test $i -eq 0; then echo zero; else echo one; fi; i=$((i + 1)); done' "zero
one"
run_test "while within if" 'i=0; if test 1 -eq 1; then while test $i -lt 2; do echo $i; i=$((i + 1)); done; echo after; fi' "0
1
after"
run_test "three control levels" 'for i in a; do if test 1 -eq 1; then j=0; while test $j -lt 1; do echo $i; j=$((j + 1)); done; fi; done' "a"
run_test "multiline nested control" 'if test 1 -eq 2
then
    echo wrong
elif test 1 -eq 1
then
    for i in a b
    do
        echo "$i"
    done
else
    echo wrong
fi' "a
b"
run_test "keyword arguments in body" 'for i in a; do echo if then elif else fi for while do done; done' "if then elif else fi for while do done"
run_test "loop in elif body" 'if test 1 -eq 2; then echo wrong; elif test 1 -eq 1; then for i in a b; do echo $i; done; else echo wrong; fi' "a
b"
run_test "nested redirection and following command" "if test 1 -eq 1; then for i in a b; do echo \$i; done; fi > $TMP_FILE; cat $TMP_FILE" "a
b"
rm -f "$TMP_FILE"

run_syntax_test() {
    local test_name="$1" cmd="$2" expected="$3" actual status=0
    actual=$("$GOSH" -c "$cmd" 2>&1) || status=$?
    if [ "$status" -eq 2 ] && [ "$actual" = "gosh: syntax error: $expected" ]; then
        echo "[PASS] $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $test_name: status=$status output=[$actual]"
        FAILED=$((FAILED + 1))
    fi
}

run_syntax_test "missing then" 'if test 1 -eq 1; echo wrong; fi' "unexpected 'fi'"
run_syntax_test "missing fi before execution" 'echo wrong; if test 1 -eq 1; then echo wrong' "expected 'fi'"
run_syntax_test "missing do" 'while test 1 -eq 2; echo wrong; done' "unexpected 'done'"
run_syntax_test "missing done" 'for i in a; do echo wrong' "expected 'done'"
run_syntax_test "missing elif condition" 'if test 1 -eq 2; then echo wrong; elif then echo wrong; fi' "expected a command in control structure"
run_syntax_test "missing elif then" 'if test 1 -eq 2; then echo wrong; elif test 1 -eq 1; echo wrong; fi' "unexpected 'fi'"
run_syntax_test "elif after else" 'if test 1 -eq 1; then echo wrong; else echo wrong; elif test 1 -eq 1; then echo wrong; fi' "unexpected 'elif'"
run_syntax_test "duplicate else" 'if test 1 -eq 1; then echo wrong; else echo wrong; else echo wrong; fi' "unexpected 'else'"
run_syntax_test "mismatched terminator" 'if test 1 -eq 1; then for i in a; do echo wrong; fi; done' "unexpected 'fi'"
run_syntax_test "malformed skipped branch" 'if test 1 -eq 1; then echo wrong; else while test 1 -eq 2; do echo wrong; fi' "unexpected 'fi'"
run_syntax_test "missing for variable" 'for ; do echo wrong; done' "expected for variable"
run_syntax_test "empty then body" 'if test 1 -eq 1; then fi' "expected a command in control structure"
run_syntax_test "stray elif" 'elif test 1 -eq 1; then echo wrong; fi' "unexpected 'elif'"
run_syntax_test "stray done" 'done' "unexpected 'done'"

# 10. Functions and Aliases
run_test "shell function" "greet() { echo \"Hello, \$1!\"; }; greet Gosh" "Hello, Gosh!"
run_test "alias expansion" "alias hi='echo welcome' && hi" "welcome"
run_test "unalias builtin" "alias foo='echo 1' && unalias foo && alias | grep foo || echo unset_ok" "unset_ok"

# 11. Builtins (export, unset, printf, test)
run_test "export and read env" "export GOSH_TEST_ENV=42 && echo \$GOSH_TEST_ENV" "42"
run_test "unset variable" "VAR=10 && unset VAR && echo \"[\$VAR]\"" "[]"
run_test "printf builtin" "printf 'num:%d str:%s\n' 42 'awesome'" "num:42 str:awesome"
# Format reuse completes each pass, defaulting missing operands to empty/zero.
run_test "printf reuse string lines" "printf '%s\n' one two three" $'one\ntwo\nthree'
run_test "printf reuse partial string cycle" "printf '[%s:%s]' one two three" "[one:two][three:]"
run_test "printf reuse mixed conversions" "printf '%s:%d:%i;' one 2 3 four 5 6" "one:2:3;four:5:6;"
run_test "printf reuse partial numeric cycle" "printf '%s:%d:%i;' one 2 3 four" "one:2:3;four:0:0;"
run_test "printf missing arguments" "printf '[%s:%d:%i]'" "[:0:0]"
run_test "printf reuse empty string operand" "printf '[%s]' '' two" "[][two]"
run_test "printf reuse literal percent" "printf '%%[%s]' one two" "%[one]%[two]"
run_test "printf reuse escaped tab" "printf '%s\t%d;' one 2 three 4" $'one\t2;three\t4;'
run_test "printf literal format ignores operands" "printf 'literal' one two" "literal"
run_test "printf percent-only format ignores operands" "printf '%%' one two" "%"
run_test "printf escapes-only format ignores operands" "printf '\t' one two" $'\t'
run_test "printf empty format ignores operands" "printf '' one two" ""
run_test "printf empty format without operands" "printf ''" ""
run_test "test builtin operators" "if [ 10 -gt 5 ]; then echo gt; fi" "gt"

# Persistent assignments must reach real children, while private variables stay private.
export GOSH_INHERITED_ASSIGN=old
export GOSH_INHERITED_EMPTY=
unset GOSH_PRIVATE_ASSIGN
run_test "exported reassignment reaches child" 'export GOSH_ASSIGN=old; GOSH_ASSIGN=new; sh -c '"'"'echo "$GOSH_ASSIGN"'"'"'' "new"
run_test "export by name retains export on assignment" 'GOSH_ASSIGN=old; export GOSH_ASSIGN; GOSH_ASSIGN=new; sh -c '"'"'echo "$GOSH_ASSIGN"'"'"'' "new"
run_test "inherited reassignment reaches child repeatedly" 'GOSH_INHERITED_ASSIGN=new; GOSH_INHERITED_ASSIGN=latest; sh -c '"'"'echo "$GOSH_INHERITED_ASSIGN"'"'"'' "latest"
run_test "empty inherited variable stays exported" 'GOSH_INHERITED_EMPTY=new; sh -c '"'"'echo "$GOSH_INHERITED_EMPTY"'"'"'' "new"
run_test "exported empty assignment reaches child" 'export GOSH_ASSIGN=old; GOSH_ASSIGN=; sh -c '"'"'echo "[$GOSH_ASSIGN]"'"'"'' "[]"
run_test "private reassignment stays private" 'GOSH_PRIVATE_ASSIGN=old; GOSH_PRIVATE_ASSIGN=new; sh -c '"'"'echo "[${GOSH_PRIVATE_ASSIGN-unset}]"'"'"'' "[unset]"
run_test "exported loop variable reaches child" 'export GOSH_ASSIGN=old; for GOSH_ASSIGN in new; do sh -c '"'"'echo "$GOSH_ASSIGN"'"'"'; done' "new"
# Only the new PATH contains this executable, so success proves exec lookup changed.
mkdir "$TEST_TMP_DIR/path"
printf '#!/bin/sh\necho path-updated\n' > "$TEST_TMP_DIR/path/gosh-path-probe"
chmod +x "$TEST_TMP_DIR/path/gosh-path-probe"
export GOSH_ASSIGN_PATH="$TEST_TMP_DIR/path"
run_test "PATH assignment updates exec lookup" 'PATH="$GOSH_ASSIGN_PATH"; gosh-path-probe' "path-updated"

# CLI operands must retain their boundaries when passed to the shell.
if GOSH="$GOSH" python3 "$REPO_ROOT/test/test_cli_args.py"; then
    PASSED=$((PASSED + 1))
else
    FAILED=$((FAILED + 1))
fi

# 12. Background Jobs
run_test "background job" "sleep 0.1 & jobs | grep -o 'sleep'" "sleep"

# Startup modes require isolated HOME directories and pseudo-terminals.
if GOSH="$GOSH" python3 "$REPO_ROOT/test/test_startup.py"; then
    PASSED=$((PASSED + 1))
else
    FAILED=$((FAILED + 1))
fi

# Summary
echo "================================================"
echo " Test Suite Finished"
echo " Passed: $PASSED"
echo " Failed: $FAILED"
echo "================================================"

if [ "$FAILED" -eq 0 ]; then
    echo -e "\033[32mALL TESTS PASSED SUCCESSFULLY!\033[0m"
    exit 0
else
    echo -e "\033[31mSOME TESTS FAILED!\033[0m"
    exit 1
fi
