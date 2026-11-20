import std;
import gosh_types;

fn is_redir_token(kind: i32) -> bool {
    kind == TOKEN_REDIR_IN || kind == TOKEN_REDIR_OUT ||
    kind == TOKEN_REDIR_APP || kind == TOKEN_REDIR_ERR ||
    kind == TOKEN_REDIR_ERR_APP || kind == TOKEN_REDIR_BOTH ||
    kind == TOKEN_REDIR_E2O || kind == TOKEN_REDIR_HEREDOC ||
    kind == TOKEN_REDIR_HERESTR
}

// Copy a here-document body from the lexer table into the redirection. Bodies
// are stored in source order, which is also the redirection token order.
fn attach_heredoc(r: Redirection&, heredocs: const Heredoc[..4]&, idx: i32&) -> bool {
    if r.kind != TOKEN_REDIR_HEREDOC { return true; }
    if idx < 0 || idx >= heredocs.len as i32 {
        print("gosh: syntax error: missing here-document body");
        return false;
    }
    format(r.body, heredocs[idx as i64].body);
    r.quoted = heredocs[idx as i64].quoted;
    idx++;
    return true;
}

// Bodies remain shell text for the executor. Walk the grammar before copying
// tokens so an inner fi/done cannot terminate an enclosing construct.
fn is_control_end(kind: i32) -> bool {
    kind == TOKEN_THEN || kind == TOKEN_ELIF || kind == TOKEN_ELSE ||
    kind == TOKEN_FI || kind == TOKEN_DO || kind == TOKEN_DONE ||
    kind == TOKEN_ESAC
}

fn copy_control_text(tokens: const Token[..64]&, start: i32, end: i32, out: u8[..512]&, max_len: i32) -> bool {
    for i in start..end {
        if tokens[i].kind == TOKEN_NEWLINE || tokens[i].kind == TOKEN_SEMI {
            if out.len + 1 > max_len {
                print("gosh: input capacity exceeded: compound text bytes (maximum ", max_len, ")");
                return false;
            }
            out.push(';');
            if out.len + 1 > max_len {
                print("gosh: input capacity exceeded: compound text bytes (maximum ", max_len, ")");
                return false;
            }
            out.push(' ');
        } else {
            if out.len > 0 && out[out.len - 1] != ' ' {
                if out.len + 1 > max_len {
                    print("gosh: input capacity exceeded: compound text bytes (maximum ", max_len, ")");
                    return false;
                }
                out.push(' ');
            }
            if out.len + tokens[i].text.len > max_len {
                print("gosh: input capacity exceeded: compound text bytes (maximum ", max_len, ")");
                return false;
            }
            format(out, tokens[i].text);
        }
    }
    return true;
}

// Stops are recognized only where a command can begin. Keyword-shaped arguments
// such as `echo done` must not close a loop.
recursive fn collect_control_text(tokens: const Token[..64]&, pos: i32&, stop1: i32, stop2: i32, stop3: i32, out: u8[..512]&, error: u8[..256]&, max_len: i32) -> bool {
    let start = pos;
    var command_start = true;
    var has_command = false;
    while pos < tokens.len && tokens[pos].kind != TOKEN_EOF {
        let kind = tokens[pos].kind;
        if (command_start || kind == TOKEN_RPAREN || kind == TOKEN_RBRACE) &&
           (kind == stop1 || kind == stop2 || kind == stop3) { break; }
        if kind == TOKEN_REDIR_HEREDOC {
            format(error, "here-documents are not supported in compound commands");
            return false;
        }
        if kind == TOKEN_SEMI || kind == TOKEN_NEWLINE || kind == TOKEN_AND || kind == TOKEN_OR || kind == TOKEN_PIPE || kind == TOKEN_AMP {
            command_start = true;
            pos++;
            continue;
        }
        if command_start && (kind == TOKEN_IF || kind == TOKEN_WHILE || kind == TOKEN_FOR || kind == TOKEN_CASE) {
            var nested = Statement {};
            if kind == TOKEN_CASE {
                if !parse_case(tokens, pos, nested, error) { return false; }
            } else if !parse_control(tokens, pos, nested, error) { return false; }
        } else if kind == TOKEN_LPAREN || kind == TOKEN_LBRACE {
            // Empty parentheses may be part of a function declaration.
            if kind == TOKEN_LPAREN && pos + 1 < tokens.len && tokens[pos + 1].kind == TOKEN_RPAREN {
                pos += 2;
                continue;
            }
            var closing: i32 = TOKEN_RBRACE;
            if kind == TOKEN_LPAREN { closing = TOKEN_RPAREN; }
            pos++;
            var grouped: u8[..512] = [];
            if !collect_control_text(tokens, pos, closing, -1, -1, grouped, error, 512) { return false; }
            if pos >= tokens.len || tokens[pos].kind != closing {
                format(error, "unclosed group in control structure");
                return false;
            }
            pos++;
        } else {
            if command_start && is_control_end(kind) {
                format(error, "unexpected '", tokens[pos].text, "'");
                return false;
            }
            pos++;
        }
        has_command = true;
        command_start = false;
    }
    if !has_command {
        format(error, "expected a command in control structure");
        return false;
    }
    return copy_control_text(tokens, start, pos, out, max_len);
}

fn expect_control_token(tokens: const Token[..64]&, pos: i32&, kind: i32, name: const u8[:], error: u8[..256]&) -> bool {
    if pos >= tokens.len || tokens[pos].kind != kind {
        format(error, "expected '", name, "'");
        return false;
    }
    pos++;
    return true;
}

recursive fn parse_control(tokens: const Token[..64]&, pos: i32&, stmt: Statement&, error: u8[..256]&) -> bool {
    let kind = tokens[pos].kind;
    pos++;
    var cond: u8[..512] = [];
    var body: u8[..512] = [];
    var alternative: u8[..512] = [];
    if kind == TOKEN_IF || kind == TOKEN_ELIF {
        stmt.kind = STMT_IF;
        if !collect_control_text(tokens, pos, TOKEN_THEN, -1, -1, cond, error, 256) { return false; }
        if !expect_control_token(tokens, pos, TOKEN_THEN, "then", error) { return false; }
        if !collect_control_text(tokens, pos, TOKEN_ELIF, TOKEN_ELSE, TOKEN_FI, body, error, 512) { return false; }
        if pos < tokens.len && tokens[pos].kind == TOKEN_ELIF {
            // Lower the remaining chain to an if in the false branch. The
            // recursive tail consumes the one fi shared by the entire chain.
            let tail_start = pos;
            var tail = Statement {};
            if !parse_control(tokens, pos, tail, error) { return false; }
            format(alternative, "if ");
            if !copy_control_text(tokens, tail_start + 1, pos, alternative, 256) { return false; }
        } else {
            if pos < tokens.len && tokens[pos].kind == TOKEN_ELSE {
                pos++;
                if !collect_control_text(tokens, pos, TOKEN_FI, -1, -1, alternative, error, 256) { return false; }
            }
            if !expect_control_token(tokens, pos, TOKEN_FI, "fi", error) { return false; }
        }
    } else {
        if kind == TOKEN_WHILE {
            stmt.kind = STMT_WHILE;
            if !collect_control_text(tokens, pos, TOKEN_DO, -1, -1, cond, error, 256) { return false; }
        } else {
            stmt.kind = STMT_FOR;
            if pos >= tokens.len || tokens[pos].kind != TOKEN_WORD {
                format(error, "expected for variable");
                return false;
            }
            if tokens[pos].text.len > 32 {
                print("gosh: input capacity exceeded: for variable bytes (maximum 32)");
                return false;
            }
            format(stmt.for_var, tokens[pos].text);
            pos++;
            if pos < tokens.len && tokens[pos].kind == TOKEN_IN {
                pos++;
                while pos < tokens.len && tokens[pos].kind != TOKEN_SEMI && tokens[pos].kind != TOKEN_NEWLINE && tokens[pos].kind != TOKEN_EOF {
                    if tokens[pos].kind != TOKEN_WORD && !(tokens[pos].kind >= TOKEN_IF && tokens[pos].kind <= TOKEN_ESAC) {
                        format(error, "expected for word or separator");
                        return false;
                    }
                    if stmt.for_words.len >= 16 {
                        print("gosh: input capacity exceeded: for words (maximum 16)");
                        return false;
                    }
                    var word: u8[..128] = [];
                    format(word, tokens[pos].text);
                    stmt.for_words.push(word);
                    pos++;
                }
            }
            while pos < tokens.len && (tokens[pos].kind == TOKEN_SEMI || tokens[pos].kind == TOKEN_NEWLINE) { pos++; }
        }
        if !expect_control_token(tokens, pos, TOKEN_DO, "do", error) { return false; }
        if !collect_control_text(tokens, pos, TOKEN_DONE, -1, -1, body, error, 512) { return false; }
        if !expect_control_token(tokens, pos, TOKEN_DONE, "done", error) { return false; }
    }
    format(stmt.cond_text, cond);
    format(stmt.body_text, body);
    format(stmt.else_text, alternative);
    return true;
}

// A case pattern is one word made of alternatives separated by '|'. The leading
// '(' is optional, and keyword-shaped words are legal patterns.
fn collect_case_pattern(tokens: const Token[..64]&, pos: i32&, out: u8[..128]&, error: u8[..256]&) -> bool {
    if pos < tokens.len && tokens[pos].kind == TOKEN_LPAREN { pos++; }
    var depth = 0;
    var has_piece = false;
    while pos < tokens.len && tokens[pos].kind != TOKEN_EOF {
        let kind = tokens[pos].kind;
        if kind == TOKEN_RPAREN && depth == 0 { break; }
        if kind == TOKEN_LPAREN { depth++; }
        else if kind == TOKEN_RPAREN { depth--; }
        var piece: u8[..128] = [];
        if kind == TOKEN_PIPE {
            format(piece, "|");
        } else if kind == TOKEN_WORD || (kind >= TOKEN_IF && kind <= TOKEN_ESAC) || kind == TOKEN_LPAREN || kind == TOKEN_RPAREN {
            format(piece, tokens[pos].text);
        } else {
            format(error, "unexpected '", tokens[pos].text, "' in case pattern");
            return false;
        }
        if out.len + piece.len > 128 {
            print("gosh: input capacity exceeded: case pattern bytes (maximum 128)");
            return false;
        }
        format(out, piece);
        has_piece = true;
        pos++;
    }
    if depth != 0 {
        format(error, "unclosed group in case pattern");
        return false;
    }
    if !has_piece {
        format(error, "expected a case pattern");
        return false;
    }
    if pos >= tokens.len || tokens[pos].kind != TOKEN_RPAREN {
        format(error, "expected ')'");
        return false;
    }
    pos++;
    return true;
}

// Collect one item body. Textual nested-case tracking keeps inner ';;' and
// 'esac' from ending the item; the body is re-parsed when it runs.
// Returns 1 after ';;', 2 with pos at 'esac', and -1 on error.
fn collect_case_body(tokens: const Token[..64]&, pos: i32&, out: u8[..512]&, error: u8[..256]&) -> i32 {
    var nested_case = 0;
    var command_start = true;
    while pos < tokens.len && tokens[pos].kind != TOKEN_EOF {
        let kind = tokens[pos].kind;
        if kind == TOKEN_SEMI && nested_case == 0 && pos + 1 < tokens.len && tokens[pos + 1].kind == TOKEN_SEMI {
            pos += 2;
            return 1;
        }
        if command_start && kind == TOKEN_ESAC {
            if nested_case == 0 { return 2; }
            nested_case--;
        }
        if command_start && kind == TOKEN_CASE { nested_case++; }
        if kind == TOKEN_NEWLINE || kind == TOKEN_SEMI {
            if out.len + 2 > 512 {
                print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                return -1;
            }
            out.push(';');
            out.push(' ');
            pos++;
            command_start = true;
            continue;
        }
        if out.len > 0 && out[out.len - 1] != ' ' {
            if out.len + 1 > 512 {
                print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                return -1;
            }
            out.push(' ');
        }
        if out.len + tokens[pos].text.len > 512 {
            print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
            return -1;
        }
        format(out, tokens[pos].text);
        pos++;
        command_start = false;
    }
    format(error, "expected 'esac'");
    return -1;
}

// Grammar:
//   case WORD in
//       [ ( ] PATTERN [ | PATTERN ]... ) [ NEWLINE ] BODY ;;
//       ...
//   esac
fn parse_case(tokens: const Token[..64]&, pos: i32&, stmt: Statement&, error: u8[..256]&) -> bool {
    pos++; // consume 'case'
    if pos >= tokens.len || tokens[pos].kind == TOKEN_EOF || tokens[pos].kind == TOKEN_IN ||
       (tokens[pos].kind != TOKEN_WORD && !(tokens[pos].kind >= TOKEN_IF && tokens[pos].kind <= TOKEN_ESAC)) {
        format(error, "expected case word");
        return false;
    }
    if tokens[pos].text.len > 128 {
        print("gosh: input capacity exceeded: case word bytes (maximum 128)");
        return false;
    }
    format(stmt.cond_text, tokens[pos].text);
    pos++;
    while pos < tokens.len && (tokens[pos].kind == TOKEN_NEWLINE || tokens[pos].kind == TOKEN_SEMI) { pos++; }
    if pos >= tokens.len || tokens[pos].kind != TOKEN_IN {
        format(error, "expected 'in'");
        return false;
    }
    pos++;

    stmt.kind = STMT_CASE;
    stmt.case_count = 0;
    loop {
        while pos < tokens.len && (tokens[pos].kind == TOKEN_NEWLINE || tokens[pos].kind == TOKEN_SEMI) { pos++; }
        if pos >= tokens.len || tokens[pos].kind == TOKEN_EOF {
            format(error, "expected 'esac'");
            return false;
        }
        if tokens[pos].kind == TOKEN_ESAC {
            pos++;
            break;
        }
        if stmt.case_count >= 8 {
            print("gosh: input capacity exceeded: case items (maximum 8)");
            return false;
        }
        var pattern: u8[..128] = [];
        if !collect_case_pattern(tokens, pos, pattern, error) { return false; }
        while pos < tokens.len && tokens[pos].kind == TOKEN_NEWLINE { pos++; }
        var body: u8[..512] = [];
        let stop = collect_case_body(tokens, pos, body, error);
        if stop < 0 { return false; }
        stmt.case_patterns.push(pattern);
        stmt.case_bodies.push(body);
        stmt.case_count = stmt.case_patterns.len as i32;
        if stop == 2 {
            pos++; // consume 'esac'
            break;
        }
    }
    return true;
}

fn parse_statements(tokens: const Token[..64]&, stmts: Statement[..8]&, heredocs: const Heredoc[..4]&, error: u8[..256]&) -> bool {
    stmts.clear();
    var pos: i32 = 0;
    var heredoc_idx: i32 = 0;
    let n = tokens.len;

    while pos < n {
        let tok = tokens[pos];

        // Skip newlines or semicolons at top level
        if tok.kind == TOKEN_NEWLINE || tok.kind == TOKEN_SEMI || tok.kind == TOKEN_EOF {
            pos++;
            continue;
        }

        if stmts.len >= 8 {
            print("gosh: input capacity exceeded: statements (maximum 8)");
            return false;
        }

        if tok.kind == TOKEN_IF || tok.kind == TOKEN_WHILE || tok.kind == TOKEN_FOR {
            var stmt = Statement {};
            if !parse_control(tokens, pos, stmt, error) { return false; }
            while pos < n && is_redir_token(tokens[pos].kind) {
                var r = Redirection { kind: tokens[pos].kind };
                pos++;
                if pos < n && tokens[pos].kind == TOKEN_WORD { format(r.target, tokens[pos].text); pos++; }
                if !attach_heredoc(r, heredocs, heredoc_idx) { return false; }
                if stmt.redirs.len >= 4 {
                    print("gosh: input capacity exceeded: redirections (maximum 4)");
                    return false;
                }
                stmt.redirs.push(r);
            }
            stmts.push(stmt);
            continue;
        }
        if tok.kind == TOKEN_CASE {
            var stmt = Statement {};
            if !parse_case(tokens, pos, stmt, error) { return false; }
            while pos < n && is_redir_token(tokens[pos].kind) {
                var r = Redirection { kind: tokens[pos].kind };
                pos++;
                if pos < n && tokens[pos].kind == TOKEN_WORD { format(r.target, tokens[pos].text); pos++; }
                if !attach_heredoc(r, heredocs, heredoc_idx) { return false; }
                if stmt.redirs.len >= 4 {
                    print("gosh: input capacity exceeded: redirections (maximum 4)");
                    return false;
                }
                stmt.redirs.push(r);
            }
            stmts.push(stmt);
            continue;
        }
        if is_control_end(tok.kind) {
            format(error, "unexpected '", tok.text, "'");
            return false;
        }

        // 4. FUNCTION definition: name() { ... } or function name { ... }
        if (tok.kind == TOKEN_WORD && pos + 2 < n && tokens[pos + 1].kind == TOKEN_LPAREN && tokens[pos + 2].kind == TOKEN_RPAREN) ||
           (tok.kind == TOKEN_FUNCTION) {
            var stmt = Statement { kind: STMT_FUNC };
            if tok.kind == TOKEN_FUNCTION {
                pos++;
                if pos < n && tokens[pos].kind == TOKEN_WORD {
                    if tokens[pos].text.len > 32 {
                        print("gosh: input capacity exceeded: function name bytes (maximum 32)");
                        return false;
                    }
                    format(stmt.func_name, tokens[pos].text);
                    pos++;
                }
            } else {
                if tok.text.len > 32 {
                    print("gosh: input capacity exceeded: function name bytes (maximum 32)");
                    return false;
                }
                format(stmt.func_name, tok.text);
                pos += 3; // name ( )
            }

            while pos < n && (tokens[pos].kind == TOKEN_NEWLINE || tokens[pos].kind == TOKEN_SEMI) { pos++; }
            if pos < n && tokens[pos].kind == TOKEN_LBRACE {
                pos++;
                var depth = 1;
                while pos < n && depth > 0 && tokens[pos].kind != TOKEN_EOF {
                    if tokens[pos].kind == TOKEN_REDIR_HEREDOC {
                        format(error, "here-documents are not supported in compound commands");
                        return false;
                    }
                    if tokens[pos].kind == TOKEN_LBRACE { depth++; }
                    else if tokens[pos].kind == TOKEN_RBRACE {
                        depth--;
                        if depth == 0 { pos++; break; }
                    }
                    if tokens[pos].kind == TOKEN_NEWLINE || tokens[pos].kind == TOKEN_SEMI {
                        if stmt.func_body.len + 1 > 512 {
                            print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                            return false;
                        }
                        stmt.func_body.push(';');
                        if stmt.func_body.len + 1 > 512 {
                            print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                            return false;
                        }
                        stmt.func_body.push(' ');
                    } else {
                        if stmt.func_body.len > 0 && stmt.func_body[stmt.func_body.len - 1] != ' ' {
                            if stmt.func_body.len + 1 > 512 {
                                print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                                return false;
                            }
                            stmt.func_body.push(' ');
                        }
                        if stmt.func_body.len + tokens[pos].text.len > 512 {
                            print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                            return false;
                        }
                        format(stmt.func_body, tokens[pos].text);
                    }
                    pos++;
                }
            }
            stmts.push(stmt);
            continue;
        }

        // 4b. Subshell: ( ... )
        if tok.kind == TOKEN_LPAREN {
            pos++;
            var stmt = Statement { kind: STMT_SUBSHELL };
            var depth = 1;
            while pos < n && depth > 0 && tokens[pos].kind != TOKEN_EOF {
                if tokens[pos].kind == TOKEN_REDIR_HEREDOC {
                    format(error, "here-documents are not supported in compound commands");
                    return false;
                }
                if tokens[pos].kind == TOKEN_LPAREN {
                    depth++;
                } else if tokens[pos].kind == TOKEN_RPAREN {
                    depth--;
                    if depth == 0 { pos++; break; }
                }
                if tokens[pos].kind == TOKEN_NEWLINE || tokens[pos].kind == TOKEN_SEMI {
                    if stmt.body_text.len + 1 > 512 {
                        print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                        return false;
                    }
                    stmt.body_text.push(';');
                    if stmt.body_text.len + 1 > 512 {
                        print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                        return false;
                    }
                    stmt.body_text.push(' ');
                } else {
                    if stmt.body_text.len > 0 && stmt.body_text[stmt.body_text.len - 1] != ' ' {
                        if stmt.body_text.len + 1 > 512 {
                            print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                            return false;
                        }
                        stmt.body_text.push(' ');
                    }
                    if stmt.body_text.len + tokens[pos].text.len > 512 {
                        print("gosh: input capacity exceeded: compound text bytes (maximum 512)");
                        return false;
                    }
                    format(stmt.body_text, tokens[pos].text);
                }
                pos++;
            }
            while pos < n && is_redir_token(tokens[pos].kind) {
                var r = Redirection { kind: tokens[pos].kind };
                pos++;
                if pos < n && tokens[pos].kind == TOKEN_WORD { format(r.target, tokens[pos].text); pos++; }
                if !attach_heredoc(r, heredocs, heredoc_idx) { return false; }
                if stmt.redirs.len >= 4 {
                    print("gosh: input capacity exceeded: redirections (maximum 4)");
                    return false;
                }
                stmt.redirs.push(r);
            }
            if pos < n && (tokens[pos].kind == TOKEN_AND || tokens[pos].kind == TOKEN_OR || tokens[pos].kind == TOKEN_SEMI || tokens[pos].kind == TOKEN_AMP) {
                if tokens[pos].kind == TOKEN_AND { stmt.op_after = OP_AND; }
                else if tokens[pos].kind == TOKEN_OR { stmt.op_after = OP_OR; }
                else if tokens[pos].kind == TOKEN_SEMI { stmt.op_after = OP_SEMI; }
                else if tokens[pos].kind == TOKEN_AMP { stmt.op_after = OP_BG; }
                pos++;
            }
            stmts.push(stmt);
            continue;
        }

        // 5. Regular Pipeline: cmd1 | cmd2 | ... [&& / || / ; / &]
        var pipe = Pipeline {};
        var current_cmd = Command {};

        while pos < n {
            let t = tokens[pos];

            if t.kind == TOKEN_PIPE {
                // End current command, push to pipeline
                current_cmd.arg_count = current_cmd.argv.len as i32;
                current_cmd.redir_count = current_cmd.redirs.len as i32;
                if pipe.cmds.len >= 4 {
                    print("gosh: input capacity exceeded: pipeline stages (maximum 4)");
                    return false;
                }
                pipe.cmds.push(current_cmd);
                current_cmd = Command {};
                pos++;
                continue;
            }

            if t.kind == TOKEN_AND || t.kind == TOKEN_OR || t.kind == TOKEN_SEMI || t.kind == TOKEN_AMP || t.kind == TOKEN_NEWLINE || t.kind == TOKEN_EOF {
                if t.kind == TOKEN_AND { pipe.op_after = OP_AND; }
                else if t.kind == TOKEN_OR { pipe.op_after = OP_OR; }
                else if t.kind == TOKEN_SEMI || t.kind == TOKEN_NEWLINE { pipe.op_after = OP_SEMI; }
                else if t.kind == TOKEN_AMP { pipe.op_after = OP_BG; current_cmd.background = true; }
                pos++;
                break;
            }

            // Redirection
            if is_redir_token(t.kind) {
                var r = Redirection { kind: t.kind };
                pos++;
                // Target file name
                if pos < n && tokens[pos].kind == TOKEN_WORD {
                    format(r.target, tokens[pos].text);
                    pos++;
                }
                if !attach_heredoc(r, heredocs, heredoc_idx) { return false; }
                if current_cmd.redirs.len >= 4 {
                    print("gosh: input capacity exceeded: redirections (maximum 4)");
                    return false;
                }
                current_cmd.redirs.push(r);
                continue;
            }

            // Word / Argument
            if t.kind == TOKEN_WORD || (t.kind >= TOKEN_IF && t.kind <= TOKEN_ESAC) {
                // Check if assignment (e.g. FOO=bar) on first word with no command yet
                if current_cmd.argv.len == 0 && !current_cmd.is_assignment {
                    let eq = find(t.text, "=");
                    if eq > 0 && ascii::is_alpha(t.text[0]) {
                        if eq > 64 {
                            print("gosh: input capacity exceeded: assignment name bytes (maximum 64)");
                            return false;
                        }
                        current_cmd.is_assignment = true;
                        format(current_cmd.assign_var, t.text[..eq]);
                        format(current_cmd.assign_val, t.text[eq + 1..]);
                        pos++;
                        continue;
                    }
                }

                if current_cmd.argv.len >= 16 {
                    print("gosh: input capacity exceeded: arguments (maximum 16)");
                    return false;
                }
                var w: u8[..128] = [];
                format(w, t.text);
                current_cmd.argv.push(w);
                pos++;
                continue;
            }

            pos++;
        }

        current_cmd.arg_count = current_cmd.argv.len as i32;
        current_cmd.redir_count = current_cmd.redirs.len as i32;
        if current_cmd.arg_count > 0 || current_cmd.is_assignment || current_cmd.redir_count > 0 {
            if pipe.cmds.len >= 4 {
                print("gosh: input capacity exceeded: pipeline stages (maximum 4)");
                return false;
            }
            pipe.cmds.push(current_cmd);
        }
        pipe.cmd_count = pipe.cmds.len as i32;

        if pipe.cmd_count > 0 {
            var stmt = Statement { kind: STMT_PIPELINE, pipeline: pipe, op_after: pipe.op_after };
            stmts.push(stmt);
        }
    }
    return true;
}
