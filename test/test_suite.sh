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

# Function and builtin redirections in the current shell.
mkdir -p "$TEST_TMP_DIR/redirs"
REDIR_DIR="$TEST_TMP_DIR/redirs"
run_test "function stdout and restoration" "f() { echo body; }; f > $REDIR_DIR/out; echo after; cat $REDIR_DIR/out" "after
body"
run_test "function stdin and stdout" "echo input > $REDIR_DIR/in; f() { cat; }; f < $REDIR_DIR/in > $REDIR_DIR/out; echo after; cat $REDIR_DIR/out" "after
input"
run_test "redirected function preserves variables" "x=before; f() { x=after; }; f > $REDIR_DIR/out; echo \$x" "after"
run_test "nested functions restore args and stdout" "inner() { echo \$1; }; outer() { inner child > $REDIR_DIR/inner; echo \$1; }; outer parent > $REDIR_DIR/out; echo [\$1]; cat $REDIR_DIR/out; cat $REDIR_DIR/inner" "[]
parent
child"
run_test "function failure status and restoration" "f() { test a = b; }; f > $REDIR_DIR/out; echo \$?; echo after" "1
after"
run_test "function failed input skips body and args" "x=before; f() { x=bad; echo bad; }; f child 2>/dev/null < $REDIR_DIR/missing; echo \$?; echo \$x [\$1]" "1
before []"
run_test "function partial setup failure restores stdout" "f() { echo bad; }; f 2>/dev/null > $REDIR_DIR/out < $REDIR_DIR/missing; echo \$?; echo after; cat $REDIR_DIR/out" "1
after"
run_test "builtin failed output skips state change" "x=before; unset x 2>/dev/null > $REDIR_DIR/missing/out; echo \$?; echo \$x" "1
before"
run_test "builtin partial setup failure restores stdout" "echo bad 2>/dev/null > $REDIR_DIR/out < $REDIR_DIR/missing; echo \$?; echo after; cat $REDIR_DIR/out" "1
after"
run_test "builtin repeated output creates both files" "echo stale > $REDIR_DIR/first; echo body > $REDIR_DIR/first > $REDIR_DIR/out; cat $REDIR_DIR/first; cat $REDIR_DIR/out" "body"
run_test "function descriptor order dup before file" "f() { sh -c 'echo err >&2'; }; f 2>&1 > $REDIR_DIR/out; echo after; cat $REDIR_DIR/out" "err
after"
run_test "function descriptor order file before dup" "f() { sh -c 'echo err >&2'; }; f > $REDIR_DIR/out 2>&1; echo after; cat $REDIR_DIR/out" "after
err"
run_test "builtin descriptor order dup before file" "command sh -c 'echo err >&2' 2>&1 > $REDIR_DIR/out; echo after; cat $REDIR_DIR/out" "err
after"
run_test "builtin descriptor order file before dup" "command sh -c 'echo err >&2' > $REDIR_DIR/out 2>&1; echo after; cat $REDIR_DIR/out" "after
err"
run_test "builtin both then stderr override" "command sh -c 'echo out; echo err >&2' &> $REDIR_DIR/out 2> $REDIR_DIR/err; cat $REDIR_DIR/out; cat $REDIR_DIR/err" "out
err"
run_test "stderr restored after builtin setup failure" "echo bad 2> $REDIR_DIR/err < $REDIR_DIR/missing; echo \$?; sh -c 'echo restored >&2'" "1
restored"

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

# Pathname expansion: isolate names and creation order from the checkout.
mkdir -p "$TEST_TMP_DIR/globs/fixtures/sub" "$TEST_TMP_DIR/globs/.hidden"
touch "$TEST_TMP_DIR/globs/fixtures/z.txt" "$TEST_TMP_DIR/globs/fixtures/A.txt" \
    "$TEST_TMP_DIR/globs/fixtures/a.txt" "$TEST_TMP_DIR/globs/fixtures/.secret.txt" \
    "$TEST_TMP_DIR/globs/fixtures/sub/b.txt" "$TEST_TMP_DIR/globs/.hidden/x.txt"
export GLOB_ROOT="$TEST_TMP_DIR/globs"
run_test "glob literal relative prefix and C ordering" 'cd "$GLOB_ROOT"; echo fixtures/*.txt' 'fixtures/A.txt fixtures/a.txt fixtures/z.txt'
run_test "glob absolute prefix" 'echo $GLOB_ROOT/fixtures/?.txt' "$GLOB_ROOT/fixtures/A.txt $GLOB_ROOT/fixtures/a.txt $GLOB_ROOT/fixtures/z.txt"
run_test "glob wildcard directory components" 'cd "$GLOB_ROOT"; echo */*/*.txt' 'fixtures/sub/b.txt'
run_test "glob explicit dot component" 'cd "$GLOB_ROOT"; echo .hidden/*.txt fixtures/.*.txt' '.hidden/x.txt fixtures/.secret.txt'
run_test "glob unmatched patterns stay literal" 'cd "$GLOB_ROOT"; echo missing/*.txt fixtures/no?.txt' 'missing/*.txt fixtures/no?.txt'
run_test "glob trailing slash requires directory" 'cd "$GLOB_ROOT"; echo fixtures/*/' 'fixtures/sub/'
run_test "glob quoted pattern stays literal" 'cd "$GLOB_ROOT"; echo "fixtures/*.txt"' 'fixtures/*.txt'
mkdir "$TEST_TMP_DIR/globs/many"
for i in {1..16}; do touch "$TEST_TMP_DIR/globs/many/$i"; done
run_test "glob capacity fails before command executes" 'cd "$GLOB_ROOT"; echo many/*' 'gosh: pathname expansion exceeds capacity' 2

# Fixed input capacities: reject the whole parse before executing a prefix.
capacity_error() {
    run_test "$1" "$2" "gosh: input capacity exceeded: $3 (maximum $4)" 2
}
printf -v words15 ' x%.0s' {1..15}
run_test "16 argv entries" "echo$words15" "${words15:1}"
capacity_error "17 argv entries reject earlier statement" "echo WRONG; echo$words15 x" arguments 16
run_test "four pipeline stages" "echo ok | cat | cat | cat" "ok"
capacity_error "fifth final pipeline stage" "echo WRONG | cat | cat | cat | cat" "pipeline stages" 4
capacity_error "sixth pipeline stage" "echo WRONG | cat | cat | cat | cat | cat" "pipeline stages" 4
run_test "four redirections" "echo ok > /dev/null > /dev/null > /dev/null > /dev/null" ""
capacity_error "fifth redirection" "echo WRONG > /dev/null > /dev/null > /dev/null > /dev/null > /dev/null" redirections 4
capacity_error "fifth compound redirection" "(echo WRONG) > /dev/null > /dev/null > /dev/null > /dev/null > /dev/null" redirections 4
printf -v statements8 'true;%.0s' {1..8}
run_test "eight statements" "$statements8" ""
capacity_error "ninth statement rejects prefix" "echo WRONG;$statements8" statements 8
printf -v separators63 ';%.0s' {1..63}
run_test "63 tokens plus EOF" "$separators63" ""
capacity_error "64 tokens reserve EOF" "$separators63;" tokens 63
printf -v word128 '%0128d' 0
run_test "128 word bytes" "echo $word128" "$word128"
capacity_error "129 word bytes" "echo WRONG; echo ${word128}x" "word bytes" 128
capacity_error "quoted word includes quote bytes" "echo '$word128'" "word bytes" 128
capacity_error "substitution word bytes" "echo \$(echo $word128)" "word bytes" 128
run_test "16 for words" "for i in$words15 x; do true; done" ""
capacity_error "17 for words" "for i in$words15 x x; do echo WRONG; done" "for words" 16
printf -v name32 'v%.0s' {1..32}
run_test "32 byte for variable" "for $name32 in x; do true; done" ""
capacity_error "33 byte for variable" "for ${name32}v in x; do echo WRONG; done" "for variable bytes" 32
run_test "32 byte function name" "$name32() { true; }" ""
capacity_error "33 byte function name" "${name32}v() { echo WRONG; }" "function name bytes" 32
printf -v name64 'v%.0s' {1..64}
run_test "64 byte assignment name" "$name64=x" ""
capacity_error "65 byte assignment name" "${name64}v=x" "assignment name bytes" 64
# Reconstructed body: 4 * (4 + 1 + 120 + 2) = 508 bytes, then true = 512.
printf -v word120 '%0120d' 0
printf -v body508 'true %s;true %s;true %s;true %s;' "$word120" "$word120" "$word120" "$word120"
run_test "512 byte function body" "f() { ${body508}true }" ""
capacity_error "513 byte function body" "f() { ${body508}truex }" "compound text bytes" 512

printf -v spaces32768 '%32768s' ''
printf '%s' "$spaces32768" > "$TMP_FILE"
run_test "32768 byte script" 'source "$TMP_FILE"' ""
printf ' ' >> "$TMP_FILE"
capacity_error "32769 byte script" 'source "$TMP_FILE"' "script bytes" 32768
rm -f "$TMP_FILE"

# Startup modes require isolated HOME directories and pseudo-terminals.
if python3 "$REPO_ROOT/test/job_control_test.py" --gosh "$GOSH"; then
    PASSED=$((PASSED + 1))
else
    FAILED=$((FAILED + 1))
fi

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
